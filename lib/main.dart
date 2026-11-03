import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

const bg = Color(0xFF090B10);
const surface = Color(0xFF131923);
const lime = Color(0xFFB8F36B);
const muted = Color(0xFF8993A3);

const mapStyle = '''
{"version":8,"sources":{"osm":{"type":"raster","tiles":["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],"tileSize":256,"attribution":"© OpenStreetMap contributors"}},"layers":[{"id":"background","type":"background","paint":{"background-color":"#10151D"}},{"id":"osm","type":"raster","source":"osm","paint":{"raster-opacity":0.94}}]}
''';

void main() => runApp(const RouteOptimizerApp());

class RouteOptimizerApp extends StatelessWidget {
  const RouteOptimizerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Route Optimizer',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: lime, surface: surface),
    ),
    home: const NavigationScreen(),
  );
}

class Place {
  final String name;
  final double lat;
  final double lon;
  const Place(this.name, this.lat, this.lon);
}

class RouteChoice {
  final List<LatLng> points;
  final double metres;
  final double seconds;
  const RouteChoice(this.points, this.metres, this.seconds);
}

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});
  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final search = TextEditingController();
  MapLibreMapController? map;
  Timer? debounce;
  StreamSubscription<Position>? gpsSubscription;
  DateTime? lastDeviationPrompt;
  double progressMetres = 0;
  bool avoidTolls = false;
  double maxDetourKm = 15;
  Position? position;
  Place? destination;
  List<Place> suggestions = [];
  List<RouteChoice> routes = [];
  int selected = 0;
  bool locating = false, searching = false, calculating = false, navigating = false;
  String status = 'PRÊT À EXPLORER';

  @override
  void dispose() {
    debounce?.cancel();
    gpsSubscription?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> locate({bool center = true}) async {
    if (locating) return;
    setState(() { locating = true; status = 'ACQUISITION GPS…'; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Active la localisation du téléphone.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Permission GPS refusée. Vérifie les réglages Android.');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      if (!mounted) return;
      setState(() { position = p; status = 'POSITION GPS ACQUISE'; });
      if (center) {
        await map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(p.latitude, p.longitude), 15));
      }
    } catch (e) {
      if (mounted) setState(() => status = cleanError(e));
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  String cleanError(Object e) => e.toString().replaceFirst('Exception: ', '');

  void onSearchChanged(String value) {
    debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => suggestions = []);
      return;
    }
    debounce = Timer(const Duration(milliseconds: 500), () => findPlaces(value.trim()));
  }

  Future<void> findPlaces(String query) async {
    setState(() => searching = true);
    try {
      final uri = Uri.https('photon.komoot.io', '/api/', {'q': query, 'limit': '6', 'lang': 'fr'});
      final response = await http.get(uri, headers: {'User-Agent': 'RouteOptimizer/0.1 personal prototype'});
      if (response.statusCode != 200) throw Exception('Service de recherche indisponible.');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List? ?? [];
      final found = features.map((f) {
        final props = f['properties'] as Map<String, dynamic>;
        final coords = f['geometry']['coordinates'] as List;
        final parts = [props['name'], props['street'], props['postcode'], props['city']]
          .where((v) => v != null && v.toString().isNotEmpty).map((v) => v.toString()).toSet();
        return Place(parts.join(', '), (coords[1] as num).toDouble(), (coords[0] as num).toDouble());
      }).where((p) => p.name.isNotEmpty).toList();
      if (mounted) setState(() => suggestions = found);
    } catch (e) {
      if (mounted) setState(() => status = 'RECHERCHE : ' + cleanError(e));
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }


  Future<void> startNavigation() async {
    if (routes.isEmpty || destination == null) return;
    setState(() { navigating = true; status = 'NAVIGATION ACTIVE — GPS EN COURS'; });
    await gpsSubscription?.cancel();
    gpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 8),
    ).listen((p) async {
      if (!mounted || !navigating || routes.isEmpty) return;
      final route = routes[selected];
      var nearest = double.infinity;
      var nearestIndex = 0;
      for (var i = 0; i < route.points.length; i++) {
        final point = route.points[i];
        final metres = Geolocator.distanceBetween(p.latitude, p.longitude, point.latitude, point.longitude);
        if (metres < nearest) { nearest = metres; nearestIndex = i; }
      }
      var remaining = 0.0;
      for (var i = nearestIndex; i < route.points.length - 1; i++) {
        final a = route.points[i], b = route.points[i + 1];
        remaining += Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
      }
      if (!mounted) return;
      setState(() {
        position = p;
        progressMetres = (route.metres - remaining).clamp(0, route.metres);
        status = nearest > 80
          ? 'ÉCART D’ITINÉRAIRE — ' + nearest.round().toString() + ' M'
          : 'NAVIGATION ACTIVE · ' + distance(progressMetres) + ' PARCOURUS';
      });
      if (nearest > 80) {
        final now = DateTime.now();
        if (lastDeviationPrompt == null || now.difference(lastDeviationPrompt!) > const Duration(seconds: 45)) {
          lastDeviationPrompt = now;
          if (mounted) {
            final recalc = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: surface,
                title: const Text('Écart détecté'),
                content: Text('Tu sembles être à ' + nearest.round().toString() + ' m du tracé. Veux-tu recalculer depuis ta position actuelle ?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('GARDER LE TRACÉ')),
                  ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('RECALCULER')),
                ],
              ),
            );
            if (recalc == true && mounted && destination != null) {
              setState(() { position = p; navigating = false; });
              await buildRoute(destination!);
              if (mounted) await startNavigation();
            }
          }
        }
      } else {
        await map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(p.latitude, p.longitude), 16));
      }
    }, onError: (Object error) {
      if (mounted) setState(() => status = 'SIGNAL GPS INSTABLE');
    });
  }

  Future<void> buildRoute(Place place) async {
    await gpsSubscription?.cancel();
    navigating = false;
    if (position == null) await locate(center: false);
    final current = position;
    if (current == null) {
      setState(() => status = 'Position GPS requise pour calculer le trajet.');
      return;
    }
    setState(() {
      calculating = true;
      destination = place;
      search.text = place.name;
      suggestions = [];
      status = 'CALCUL DE L’ITINÉRAIRE…';
    });
    try {
      final path = '/route/v1/driving/' +
        current.longitude.toString() + ',' + current.latitude.toString() + ';' +
        place.lon.toString() + ',' + place.lat.toString();
      final uri = Uri.https('router.project-osrm.org', path, {
        'overview': 'full', 'geometries': 'geojson', 'alternatives': 'true', 'steps': 'false'
      });
      final response = await http.get(uri, headers: {'User-Agent': 'RouteOptimizer/0.1'});
      if (response.statusCode != 200) throw Exception('Moteur de calcul indisponible.');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') throw Exception('Aucun itinéraire trouvé.');
      final found = (data['routes'] as List).map((r) {
        final coords = r['geometry']['coordinates'] as List;
        final points = coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
        return RouteChoice(points, (r['distance'] as num).toDouble(), (r['duration'] as num).toDouble());
      }).toList();
      found.sort((a, b) => a.seconds.compareTo(b.seconds));
      final fastest = found.isEmpty ? 0.0 : found.first.metres;
      final filtered = found.where((r) => r.metres <= fastest + maxDetourKm * 1000).toList();
      if (!mounted) return;
      setState(() {
        routes = filtered.isEmpty ? found : filtered;
        selected = 0;
        progressMetres = 0;
        status = routes.length.toString() + ' OPTION(S) · DÉTOUR MAX ' + maxDetourKm.toStringAsFixed(0) + ' KM';
      });
      await drawRoute();
      await map?.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            (current.latitude < place.lat ? current.latitude : place.lat) - 0.025,
            (current.longitude < place.lon ? current.longitude : place.lon) - 0.025),
          northeast: LatLng(
            (current.latitude > place.lat ? current.latitude : place.lat) + 0.025,
            (current.longitude > place.lon ? current.longitude : place.lon) + 0.025),
        ), left: 35, top: 120, right: 35, bottom: 285));
    } catch (e) {
      if (mounted) setState(() => status = cleanError(e));
    } finally {
      if (mounted) setState(() => calculating = false);
    }
  }

  Future<void> drawRoute() async {
    if (map == null || routes.isEmpty) return;
    await map!.clearLines();
    await map!.addLine(LineOptions(
      geometry: routes[selected].points,
      lineColor: '#B8F36B',
      lineWidth: 5,
      lineOpacity: 0.95,
    ));
  }

  String distance(double metres) => metres >= 1000
    ? (metres / 1000).toStringAsFixed(1) + ' km'
    : metres.round().toString() + ' m';

  String duration(double seconds) {
    final mins = (seconds / 60).round();
    return mins >= 60 ? (mins ~/ 60).toString() + ' h ' + (mins % 60).toString() + ' min' : mins.toString() + ' min';
  }

  @override
  Widget build(BuildContext context) {
    final route = routes.isEmpty ? null : routes[selected];
    return Scaffold(
      body: Stack(children: [
        MapLibreMap(
          styleString: mapStyle,
          initialCameraPosition: const CameraPosition(target: LatLng(47.2184, -1.5536), zoom: 11.5),
          myLocationEnabled: position != null,
          myLocationTrackingMode: MyLocationTrackingMode.none,
          compassEnabled: false,
          attributionButtonPosition: AttributionButtonPosition.bottomLeft,
          onMapCreated: (controller) => map = controller,
          onStyleLoadedCallback: () { if (routes.isNotEmpty) drawRoute(); },
        ),
        SafeArea(child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(children: [
              Container(width: 42, height: 42,
                decoration: BoxDecoration(color: bg.withValues(alpha: .94), borderRadius: BorderRadius.circular(13), border: Border.all(color: lime.withValues(alpha: .45))),
                child: const Icon(Icons.alt_route, color: lime)),
              const SizedBox(width: 10),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ROUTE OPTIMIZER', style: TextStyle(fontSize: 13, letterSpacing: 2.1, fontWeight: FontWeight.w900)),
                Text('NAVIGATION INTELLIGENTE', style: TextStyle(fontSize: 9, color: muted, letterSpacing: 1.6)),
              ])),
              _GpsBadge(active: position != null),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              Container(
                decoration: BoxDecoration(color: surface.withValues(alpha: .97), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: .08))),
                child: TextField(
                  controller: search,
                  onChanged: onSearchChanged,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Rechercher une destination…',
                    hintStyle: const TextStyle(color: muted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: lime),
                    suffixIcon: searching || calculating
                      ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: lime)))
                      : IconButton(icon: const Icon(Icons.close, color: muted), onPressed: () {
                          search.clear();
                          setState(() { suggestions = []; routes = []; destination = null; navigating = false; status = 'PRÊT À EXPLORER'; });
                          map?.clearLines();
                        }),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 17),
                  ),
                ),
              ),
              if (suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
                  child: Column(children: suggestions.map((p) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined, color: lime, size: 19),
                    title: Text(p.name, style: const TextStyle(fontSize: 12)),
                    onTap: () => buildRoute(p),
                  )).toList()),
                ),
            ]),
          ),
          const Spacer(),
          Align(alignment: Alignment.centerRight, child: Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 12),
            child: FloatingActionButton.small(
              heroTag: 'gps', backgroundColor: surface, onPressed: () => locate(),
              child: locating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: lime))
                : const Icon(Icons.my_location, color: lime),
            ),
          )),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 22),
            decoration: BoxDecoration(color: bg.withValues(alpha: .98), borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), border: Border.all(color: Colors.white.withValues(alpha: .08))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: lime, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(status.toUpperCase(), style: const TextStyle(color: muted, fontSize: 9, letterSpacing: 1.4, fontWeight: FontWeight.w700))),
                const Text('V 0.1.0', style: TextStyle(color: muted, fontSize: 9)),
              ]),
              const SizedBox(height: 14),
              if (route == null) ...[
                const Text('Votre prochain trajet.', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                const Text('Recherchez une destination pour afficher le trajet et ses options.', style: TextStyle(color: muted, fontSize: 12, height: 1.4)),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(
                  onPressed: () => locate(),
                  icon: const Icon(Icons.gps_fixed, size: 17),
                  label: const Text('LOCALISER MA POSITION'),
                  style: OutlinedButton.styleFrom(foregroundColor: lime, side: const BorderSide(color: lime), padding: const EdgeInsets.symmetric(vertical: 14)),
                )),
              ] else ...[
                Text(destination?.name ?? 'Destination', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 13),
                Row(children: [
                  _Metric(value: distance(route.metres), label: 'DISTANCE'),
                  const SizedBox(width: 28),
                  _Metric(value: duration(route.seconds), label: 'DURÉE ESTIMÉE'),
                  const Spacer(),
                  Text((selected + 1).toString() + '/' + routes.length.toString(), style: const TextStyle(color: lime, fontWeight: FontWeight.w800)),
                ]),
                if (routes.length > 1) ...[
                  const SizedBox(height: 13),
                  SizedBox(height: 38, child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: routes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => ChoiceChip(
                      label: Text('OPTION ' + (i + 1).toString() + ' · ' + duration(routes[i].seconds)),
                      selected: selected == i,
                      selectedColor: lime,
                      backgroundColor: surface,
                      labelStyle: TextStyle(color: selected == i ? bg : Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                      onSelected: (_) async { setState(() => selected = i); await drawRoute(); },
                    ),
                  )),
                ],
                if (navigating) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Text('PROGRESSION', style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1)),
                    const Spacer(),
                    Text(distance(progressMetres) + ' / ' + distance(route.metres), style: const TextStyle(color: lime, fontSize: 11, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 5),
                  LinearProgressIndicator(value: route.metres <= 0 ? 0 : (progressMetres / route.metres).clamp(0, 1), backgroundColor: surface, color: lime, minHeight: 4),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context, backgroundColor: surface,
                      builder: (context) => StatefulBuilder(builder: (context, setSheetState) => Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('PRÉFÉRENCES DU TRAJET', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                          const SizedBox(height: 18),
                          Text('Détour supplémentaire maximal : ' + maxDetourKm.toStringAsFixed(0) + ' km'),
                          Slider(value: maxDetourKm, min: 0, max: 50, divisions: 10, activeColor: lime,
                            label: maxDetourKm.toStringAsFixed(0) + ' km',
                            onChanged: (v) => setSheetState(() { maxDetourKm = v; }),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero, activeThumbColor: lime,
                            title: const Text('Préférer les routes sans péage'),
                            subtitle: const Text('Le service actuel ne fournit pas de données de péage fiables : cette préférence ne peut pas encore filtrer les trajets.'),
                            value: avoidTolls,
                            onChanged: (v) => setSheetState(() { avoidTolls = v; }),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('APPLIQUER'))),
                        ]),
                      )),
                    ),
                    icon: const Icon(Icons.tune, size: 16), label: const Text('OPTIONS'),
                    style: OutlinedButton.styleFrom(foregroundColor: lime, side: const BorderSide(color: lime)),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: ElevatedButton(
                    onPressed: navigating ? () async {
                      await gpsSubscription?.cancel();
                      if (mounted) setState(() { navigating = false; status = 'TRAJET EN PAUSE'; });
                    } : startNavigation,
                    style: ElevatedButton.styleFrom(backgroundColor: lime, foregroundColor: bg, padding: const EdgeInsets.symmetric(vertical: 15)),
                    child: Text(navigating ? 'PAUSE' : 'DÉMARRER', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                  )),
                ]),
              ],
              const SizedBox(height: 9),
              const Text('CARTOGRAPHIE © OPENSTREETMAP · SERVICES DE DÉMONSTRATION', style: TextStyle(color: Color(0xFF657080), fontSize: 8, letterSpacing: .6)),
            ]),
          ),
        ])),
      ]),
    );
  }
}

class _GpsBadge extends StatelessWidget {
  final bool active;
  const _GpsBadge({required this.active});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(30), border: Border.all(color: active ? lime.withValues(alpha: .5) : Colors.white12)),
    child: Row(children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(color: active ? lime : muted, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(active ? 'GPS ON' : 'GPS OFF', style: TextStyle(fontSize: 9, color: active ? lime : muted, fontWeight: FontWeight.w800, letterSpacing: .8)),
    ]),
  );
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  const _Metric({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: lime)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 8, color: muted, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
  ]);
}
