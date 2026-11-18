import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:route_optimizer/core/theme.dart';
import 'package:route_optimizer/state/navigation_state.dart';
import 'package:route_optimizer/ui/screens/navigation_screen.dart';

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
        scaffoldBackgroundColor: AppTheme.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppTheme.lime,
          surface: AppTheme.surface,
        ),
      ),
      home: const NavigationScreen(),
    );
  }
}
