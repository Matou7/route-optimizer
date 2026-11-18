import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

// === CONSTANTES & THÈME ===
const Color appBg = Color(0xFF090B10);
const Color appSurface = Color(0xFF131923);
const Color appLime = Color(0xFFB8F36B);
const Color appMuted = Color(0xFF8993A3);

const String mapStyleConfig = '''
{
  "version": 8,
  "sources": {
    "osm": {
      "type": "raster",
      "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      "tileSize": 256,
      "attribution": "© OpenStreetMap contributors"
    }
  },
  "layers": [
    {
      "id": "background",
      "type": "background",
      "paint": {"background-color": "#10151D"}
    },
    {
      "id": "osm",
      "type": "raster",
      "source": "osm",
      "paint": {"raster-opacity": 0.94}
    }
  ]
}
''';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NavigationState()),
      ],
      child: const RouteOptimizerApp(),
    ),
  );
}

class RouteOptimizerApp extends StatelessWidget {
  const RouteOptimizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Route Optimizer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: appBg,
        colorScheme: const ColorScheme.dark(
          primary: appLime,
          surface: appSurface,
        ),
      ),
      home: const NavigationScreen(),
    );
  }
}

// === MODÈLES DE DONNÉES ===
class Place {
  final String name;
  final double lat;
  final double lon;
  const Place({required this.name, required this.lat, required this.lon});
}

class RouteStep {
  final String instruction;
  final double metres;
  const RouteStep({required this.instruction, required this.metres});
}

class RouteChoice {
  final List<LatLng> points;
  final double metres;
  final double seconds;
  final List<RouteStep> steps;
  const RouteChoice({required this.points, required this.metres, required this.seconds, required this.steps});
}

// === MOTEUR D'ÉTAT (PROVIDER) ===
enum NavMode { idle, locating, searching, calculating, navigating }

class NavigationState extends ChangeNotifier {
  NavMode mode = NavMode.idle;
  String statusMessage = 'PRÊT À EXPLORER';
  String errorMessage = '';

  Position? currentPosition;
  double mapBearing = 0.0;
  
  Place? destination;
  List<Place> searchSuggestions = [];
  List<RouteChoice> availableRoutes = [];
  int selectedRouteIndex = 0;
  
  double progressMetres = 0;
  double maxDetourKm = 15.0;
  bool avoidTolls = false;
  
  StreamSubscription<Position>? _gpsSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _debounceTimer;
  DateTime? _lastDeviationPrompt;
  
  MapLibreMapController? mapController;

  NavigationState() {
    _initCompass();
  }

  void _initCompass() {
    _compassSubscription = FlutterCompass.events?.listen((event) {
      final heading = event.heading;
      if (heading == null || !heading.isFinite) return;
      if ((currentPosition?.speed ?? 0) < 1.5) {
        mapBearing = (heading + 360) % 360;
        if (mode == NavMode.navigating && currentPosition != null) {
          _updateCamera(LatLng(currentPosition!.latitude, currentPosition!.longitude), mapBearing, 45);
        } else {
          notifyListeners();
        }
      }
    });
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _compassSubscription?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> locateHardware({bool centerMap = true}) async {
    if (mode == NavMode.locating) return;
    _setMode(NavMode.locating, 'ACQUISITION HARDWARE GPS…');
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Active la localisation du téléphone.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Permission GPS refusée.');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      currentPosition = pos;
      errorMessage = '';
      _setMode(NavMode.idle, 'POSITION SYNCHRONISÉE');
      if (centerMap) {
        _updateCamera(LatLng(pos.latitude, pos.longitude), 0, 0, zoom: 15);
      }
    } catch (e) {
      _handleError(e, 'ERREUR GPS');
    }
  }

  void onSearchQuery(String query) {
    _debounceTimer?.cancel();
    if (query.trim().length < 3) {
      searchSuggestions = [];
      notifyListeners();
      return;
    }
    _setMode(NavMode.searching, 'RECHERCHE EN COURS…');
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final uri = Uri.https('photon.komoot.io', '/api/', {'q': query.trim(), 'limit': '6', 'lang': 'fr'});
        final response = await http.get(uri, headers: {'User-Agent': 'RouteOptimizer/0.2'});
        if (response.statusCode != 200) throw Exception('Recherche indisponible.');
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List? ?? [];
        searchSuggestions = features.map((f) {
          final props = f['properties'] as Map<String, dynamic>;
          final coords = f['geometry']['coordinates'] as List;
          final parts = [props['name'], props['street'], props['postcode'], props['city']]
              .where((v) => v != null && v.toString().isNotEmpty)
              .map((v) => v.toString())
              .toSet();
          return Place(name: parts.join(', '), lat: (coords[1] as num).toDouble(), lon: (coords[0] as num).toDouble());
        }).where((p) => p.name.isNotEmpty).toList();
        _setMode(NavMode.idle, 'CIBLES TROUVÉES');
      } catch (e) {
        _handleError(e, 'ERREUR RÉSEAU');
      }
    });
  }

  Future<void> requestRouteCalculation(Place target) async {
    await _gpsSubscription?.cancel();
    if (currentPosition == null) {
      await locateHardware(centerMap: false);
      if (currentPosition == null) return;
    }
    destination = target;
    searchSuggestions = [];
    _setMode(NavMode.calculating, 'CALCUL DES VECTEURS…');

    try {
      final path = '/route/v1/driving/${currentPosition!.longitude},${currentPosition!.latitude};${target.lon},${target.lat}';
      final uri = Uri.https('router.project-osrm.org', path, {
        'overview': 'full', 'geometries': 'geojson', 'alternatives': 'true', 'steps': 'true'
      });
      final response = await http.get(uri, headers: {'User-Agent': 'RouteOptimizer/0.2'});
      if (response.statusCode != 200) throw Exception('Moteur OSRM déconnecté.');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') throw Exception('Aucune trajectoire.');

      final routes = (data['routes'] as List).map((r) {
        final coords = r['geometry']['coordinates'] as List;
        final points = coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
        final legs = r['legs'] as List? ?? [];
        final stepList = <RouteStep>[];
        for (final leg in legs) {
          for (final step in (leg['steps'] as List? ?? [])) {
            final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
            final type = (maneuver['type'] ?? 'continue').toString();
            final modifier = (maneuver['modifier'] ?? '').toString();
            final road = (step['name'] ?? '').toString();
            final action = _maneuverLabel(type, modifier);
            final instruction = road.isEmpty ? action : '$action sur $road';
            stepList.add(RouteStep(instruction: instruction, metres: (step['distance'] as num? ?? 0).toDouble()));
          }
        }
        return RouteChoice(points: points, metres: (r['distance'] as num).toDouble(), seconds: (r['duration'] as num).toDouble(), steps: stepList);
      }).toList();

      routes.sort((a, b) => a.seconds.compareTo(b.seconds));
      final fastest = routes.isEmpty ? 0.0 : routes.first.metres;
      availableRoutes = routes.where((r) => r.metres <= fastest + maxDetourKm * 1000).toList();
      if (availableRoutes.isEmpty) availableRoutes = routes;
      
      selectedRouteIndex = 0;
      progressMetres = 0;
      _setMode(NavMode.idle, '${availableRoutes.length} OPTION(S)');
      await drawCurrentRoute();
      _frameRouteBounds();
    } catch (e) {
      _handleError(e, 'ÉCHEC CALCUL');
    }
  }

  Future<void> selectRoute(int index) async {
    selectedRouteIndex = index;
    notifyListeners();
    await drawCurrentRoute();
  }

  Future<void> startNavigation() async {
    if (availableRoutes.isEmpty || destination == null) return;
    _setMode(NavMode.navigating, 'NAVIGATION ACTIVE');
    await _gpsSubscription?.cancel();
    _updateCamera(LatLng(currentPosition!.latitude, currentPosition!.longitude), mapBearing, 45, zoom: 18);

    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 4),
    ).listen((pos) {
      currentPosition = pos;
      if (pos.speed >= 1.5 && pos.heading.isFinite && pos.heading >= 0) {
        mapBearing = (pos.heading + 360) % 360;
      }
      _processNavigationFrame(pos);
    }, onError: (e) {
      _handleError(e, 'PERTE GPS');
    });
  }

  void pauseNavigation() {
    _gpsSubscription?.cancel();
    _setMode(NavMode.idle, 'TRAJET EN PAUSE');
  }

  void clearSession() {
    pauseNavigation();
    destination = null;
    availableRoutes = [];
    searchSuggestions = [];
    progressMetres = 0;
    mapController?.clearLines();
    _setMode(NavMode.idle, 'PRÊT À EXPLORER');
  }

  void updateSettings(double detour, bool tolls) {
    maxDetourKm = detour;
    avoidTolls = tolls;
    notifyListeners();
  }

  void _processNavigationFrame(Position pos) {
    final route = availableRoutes[selectedRouteIndex];
    double nearestDist = double.infinity;
    int nearestIndex = 0;
    
    for (int i = 0; i < route.points.length; i++) {
      final point = route.points[i];
      final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, point.latitude, point.longitude);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestIndex = i;
      }
    }

    double remaining = 0.0;
    for (int i = nearestIndex; i < route.points.length - 1; i++) {
      remaining += Geolocator.distanceBetween(route.points[i].latitude, route.points[i].longitude, route.points[i+1].latitude, route.points[i+1].longitude);
    }
    progressMetres = (route.metres - remaining).clamp(0, route.metres);

    if (nearestDist > 80) {
      statusMessage = 'ÉCART — ${nearestDist.round()} M';
      _checkDeviationPrompt();
    } else {
      statusMessage = 'NAVIGATION ACTIVE · ${_formatDistance(progressMetres)}';
      _updateCamera(LatLng(pos.latitude, pos.longitude), mapBearing, 45, zoom: 18);
    }
    notifyListeners();
  }

  void _checkDeviationPrompt() {
    final now = DateTime.now();
    if (_lastDeviationPrompt == null || now.difference(_lastDeviationPrompt!) > const Duration(seconds: 45)) {
      _lastDeviationPrompt = now;
      errorMessage = 'DEV_ALERT';
    }
  }

  void resolveDeviation(bool recalculate) {
    errorMessage = '';
    if (recalculate && destination != null) {
      pauseNavigation();
      requestRouteCalculation(destination!).then((_) {
        if (availableRoutes.isNotEmpty) startNavigation();
      });
    }
  }

  Future<void> drawCurrentRoute() async {
    if (mapController == null || availableRoutes.isEmpty) return;
    await mapController!.clearLines();
    await mapController!.addLine(LineOptions(
      geometry: availableRoutes[selectedRouteIndex].points,
      lineColor: '#B8F36B',
      lineWidth: 6,
      lineOpacity: 0.95,
      lineJoin: 'round',
      lineCap: 'round',
    ));
  }

  void _updateCamera(LatLng target, double bearing, double tilt, {double zoom = 16}) {
    mapController?.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: target, zoom: zoom, bearing: bearing, tilt: tilt)
    ));
  }

  void _frameRouteBounds() {
    if (currentPosition == null || destination == null) return;
    final lat1 = currentPosition!.latitude;
    final lon1 = currentPosition!.longitude;
    final lat2 = destination!.lat;
    final lon2 = destination!.lon;
    mapController?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(lat1 < lat2 ? lat1 - 0.025 : lat2 - 0.025, lon1 < lon2 ? lon1 - 0.025 : lon2 - 0.025),
        northeast: LatLng(lat1 > lat2 ? lat1 + 0.025 : lat2 + 0.025, lon1 > lon2 ? lon1 + 0.025 : lon2 + 0.025),
      ),
      left: 35, top: 120, right: 35, bottom: 300,
    ));
  }

  void _setMode(NavMode m, String msg) {
    mode = m;
    statusMessage = msg;
    notifyListeners();
  }

  void _handleError(Object e, String prefix) {
    mode = NavMode.idle;
    statusMessage = 'EN ATTENTE';
    errorMessage = '$prefix: ${e.toString().replaceAll('Exception: ', '')}';
    notifyListeners();
  }

  RouteStep? get nextStep {
    if (availableRoutes.isEmpty || availableRoutes[selectedRouteIndex].steps.isEmpty) return null;
    double covered = 0.0;
    for (final step in availableRoutes[selectedRouteIndex].steps) {
      covered += step.metres;
      if (covered > progressMetres + 5) return step;
    }
    return availableRoutes[selectedRouteIndex].steps.last;
  }

  double get nextStepDistance {
    if (availableRoutes.isEmpty || availableRoutes[selectedRouteIndex].steps.isEmpty) return 0;
    double covered = 0.0;
    for (final step in availableRoutes[selectedRouteIndex].steps) {
      covered += step.metres;
      if (covered > progressMetres + 5) return (covered - progressMetres).clamp(0, step.metres);
    }
    return 0;
  }

  String _formatDistance(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
  bool get hasActiveRoute => availableRoutes.isNotEmpty;
  RouteChoice? get currentRoute => hasActiveRoute ? availableRoutes[selectedRouteIndex] : null;

  String _maneuverLabel(String type, String modifier) {
    if (type == 'depart') return 'Démarrer';
    if (type == 'arrive') return 'Cible atteinte';
    if (type == 'roundabout' || type == 'rotary') return 'Rond-point';
    if (type == 'merge') return 'Rejoindre la voie';
    if (type == 'fork') return modifier.contains('left') ? 'Garder la gauche' : 'Garder la droite' : 'Maintenir';
    if (type == 'turn' || type == 'continue' || type == 'new name') {
      if (modifier.contains('uturn')) return 'Demi-tour';
      if (modifier.contains('left')) return 'Tourner à gauche';
      if (modifier.contains('right')) return 'Tourner à droite';
      return 'Continuer';
    }
    return 'Continuer';
  }
}

// === INTERFACE UTILISATEUR ===
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});
  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NavigationState>().addListener(_onStateChanged);
    });
  }

  void _onStateChanged() {
    final state = context.read<NavigationState>();
    if (state.errorMessage == 'DEV_ALERT') {
      _showDeviationDialog(state);
    } else if (state.errorMessage.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.errorMessage), backgroundColor: Colors.red[900]),
      );
      state.errorMessage = '';
    }
  }

  Future<void> _showDeviationDialog(NavigationState state) async {
    final recalc = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: appSurface,
        title: const Text('DÉVIATION DÉTECTÉE'),
        content: const Text('Voulez-vous recalculer l\'itinéraire depuis votre position ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('IGNORER')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('RECALCULER')),
        ],
      ),
    );
    state.resolveDeviation(recalc ?? false);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Stack(
        children: [
          MapLayer(),
          SafeArea(child: HudLayer()),
        ],
      ),
    );
  }
}

class MapLayer extends StatelessWidget {
  const MapLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<NavigationState>(context, listen: false);
    return MapLibreMap(
      styleString: mapStyleConfig,
      initialCameraPosition: const CameraPosition(target: LatLng(47.2184, -1.5536), zoom: 11.5),
      myLocationEnabled: true,
      myLocationTrackingMode: MyLocationTrackingMode.none,
      compassEnabled: false,
      attributionButtonPosition: AttributionButtonPosition.bottomLeft,
      onMapCreated: (controller) => state.mapController = controller,
      onStyleLoadedCallback: () {
        if (state.hasActiveRoute) state.drawCurrentRoute();
      },
    );
  }
}

class HudLayer extends StatefulWidget {
  const HudLayer({super.key});
  @override
  State<HudLayer> createState() => _HudLayerState();
}

class _HudLayerState extends State<HudLayer> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NavigationState>();
    final isNavigating = state.mode == NavMode.navigating;

    return Column(
      children: [
        if (!isNavigating) ...[
          _buildTopHeader(state),
          _buildSearchBar(state),
        ],
        const Spacer(),
        if (!isNavigating)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 12),
              child: FloatingActionButton.small(
                heroTag: 'gps_sync',
                backgroundColor: appSurface,
                onPressed: () => state.locateHardware(),
                child: state.mode == NavMode.locating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: appLime))
                  : const Icon(Icons.my_location, color: appLime),
              ),
            ),
          ),
        _buildBottomPanel(state),
      ],
    );
  }

  Widget _buildTopHeader(NavigationState state) {
    final gpsActive = state.currentPosition != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: appBg.withOpacity(0.94),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: appLime.withOpacity(0.45)),
            ),
            child: const Icon(Icons.alt_route, color: appLime),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ROUTE OPTIMIZER', style: TextStyle(fontSize: 13, letterSpacing: 2.1, fontWeight: FontWeight.w900)),
                Text('NAVIGATION TEMPS RÉEL', style: TextStyle(fontSize: 9, color: appMuted, letterSpacing: 1.6)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: appSurface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: gpsActive ? appLime.withOpacity(0.5) : Colors.white12),
            ),
            child: Row(
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: gpsActive ? appLime : appMuted, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(gpsActive ? 'GPS ON' : 'GPS OFF', style: TextStyle(fontSize: 9, color: gpsActive ? appLime : appMuted, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(NavigationState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: appSurface.withOpacity(0.97),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: state.onSearchQuery,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher une destination…',
                hintStyle: const TextStyle(color: appMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: appLime),
                suffixIcon: (state.mode == NavMode.searching || state.mode == NavMode.calculating)
                  ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: appLime)))
                  : IconButton(
                      icon: const Icon(Icons.close, color: appMuted),
                      onPressed: () {
                        _searchController.clear();
                        state.clearSession();
                      },
                    ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 17),
              ),
            ),
          ),
          if (state.searchSuggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
              child: Column(
                children: state.searchSuggestions.map((p) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, color: appLime, size: 19),
                  title: Text(p.name, style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    state.requestRouteCalculation(p);
                  },
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(NavigationState state) {
    final route = state.currentRoute;
    final isNav = state.mode == NavMode.navigating;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 22),
      decoration: BoxDecoration(
        color: appBg.withOpacity(0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: appLime, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(state.statusMessage, style: const TextStyle(color: appMuted, fontSize: 9, letterSpacing: 1.4, fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 14),
          if (route == null) ...[
            const Text('Votre prochain trajet.', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            const Text('Recherchez une destination pour afficher le trajet et ses options.', style: TextStyle(color: appMuted, fontSize: 12, height: 1.4)),
          ] else ...[
            Text(state.destination?.name ?? 'Destination', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 13),
            Row(
              children: [
                _metric(_dist(isNav ? (route.metres - state.progressMetres).clamp(0, route.metres) : route.metres), isNav ? 'RESTANTE' : 'DISTANCE'),
                const SizedBox(width: 28),
                _metric(isNav ? _time((route.seconds * (route.metres <= 0 ? 0 : (route.metres - state.progressMetres) / route.metres)).clamp(0, route.seconds)) : _time(route.seconds), isNav ? 'ARRIVÉE' : 'DURÉE'),
                const Spacer(),
                if (!isNav) Text('${state.selectedRouteIndex + 1}/${state.availableRoutes.length}', style: const TextStyle(color: appLime, fontWeight: FontWeight.w800)),
              ],
            ),
            if (!isNav && state.availableRoutes.length > 1) ...[
              const SizedBox(height: 13),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.availableRoutes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) => ChoiceChip(
                    label: Text('OPTION ${i + 1} · ${_time(state.availableRoutes[i].seconds)}'),
                    selected: state.selectedRouteIndex == i,
                    selectedColor: appLime,
                    backgroundColor: appSurface,
                    labelStyle: TextStyle(color: state.selectedRouteIndex == i ? appBg : Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                    onSelected: (_) => state.selectRoute(i),
                  ),
                ),
              ),
            ],
            if (isNav) ...[
              if (state.nextStep != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(color: appSurface, borderRadius: BorderRadius.circular(14), border: Border.all(color: appLime.withOpacity(0.45))),
                  child: Row(
                    children: [
                      const Icon(Icons.turn_right, color: appLime, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_dist(state.nextStepDistance).toUpperCase(), style: const TextStyle(color: appLime, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                            const SizedBox(height: 3),
                            Text(state.nextStep!.instruction, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  const Text('PROGRESSION', style: TextStyle(color: appMuted, fontSize: 9, letterSpacing: 1)),
                  const Spacer(),
                  Text('${_dist(state.progressMetres)} / ${_dist(route.metres)}', style: const TextStyle(color: appLime, fontSize: 11, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 5),
              LinearProgressIndicator(value: route.metres <= 0 ? 0 : (state.progressMetres / route.metres).clamp(0, 1), backgroundColor: appSurface, color: appLime, minHeight: 4),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (!isNav)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showSettingsSheet(context, state),
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('OPTIONS'),
                      style: OutlinedButton.styleFrom(foregroundColor: appLime, side: const BorderSide(color: appLime)),
                    ),
                  ),
                if (!isNav) const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => isNav ? state.pauseNavigation() : state.startNavigation(),
                    style: ElevatedButton.styleFrom(backgroundColor: appLime, foregroundColor: appBg, padding: const EdgeInsets.symmetric(vertical: 15)),
                    child: Text(isNav ? 'PAUSE' : 'DÉMARRER', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: appLime)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 8, color: appMuted, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
    ],
  );

  void _showSettingsSheet(BuildContext context, NavigationState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: appSurface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PRÉFÉRENCES', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 18),
              Text('Détour maximal : ${state.maxDetourKm.toStringAsFixed(0)} km'),
              Slider(
                value: state.maxDetourKm, min: 0, max: 50, divisions: 10, activeColor: appLime,
                label: '${state.maxDetourRemarque ?? state.maxDetourKm.toStringAsFixed(0)} km',
                onChanged: (v) => setSheetState(() => state.updateSettings(v, state.avoidTolls)),
              ),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('APPLIQUER'))),
            ],
          ),
        ),
      ),
    );
  }

  String _dist(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
  String _time(double s) {
    final mins = (s / 60).round();
    return mins >= 60 ? '${mins ~/ 60} h ${mins % 60} min' : '$mins min';
  }
}