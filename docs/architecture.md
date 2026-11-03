# Architecture cible

## 1. État

Ce document décrit une cible technique, pas une implémentation déjà présente. Le dépôt est actuellement documentaire.

## 2. Stack envisagée

- **Flutter / Dart** : application Android en priorité, avec possibilité d'extension.
- **MapLibre** : affichage cartographique. MapLibre est un moteur de rendu, pas un fournisseur de cartes ni un moteur de routage.
- **GPS natif via plugins Flutter maintenus** : position, permissions et suivi.
- **Moteur de routage open source** : à sélectionner après prototype et validation de la faisabilité offline.
- **Stockage local** : préférences, cartes téléchargées et état de navigation si nécessaire.

Chaque dépendance devra être évaluée selon sa licence, sa maintenance, sa taille et ses besoins réseau.

## 3. Couches logicielles

```text
lib/
├── app/                 # démarrage, thème, navigation entre écrans
├── core/                # erreurs, configuration, utilitaires
├── features/
│   ├── map/             # carte et position
│   ├── search/          # recherche de destinations
│   ├── routing/         # calcul et comparaison des itinéraires
│   ├── navigation/      # suivi GPS et déviation
│   ├── traffic/         # événements et fraîcheur des données
│   └── settings/        # préférences
├── data/
│   ├── repositories/    # implémentations des contrats
│   ├── sources/         # sources locales et distantes
│   └── models/          # modèles de données
└── main.dart
```

Cette arborescence sera créée au moment du véritable bootstrap Flutter.

## 4. Flux de données

1. L'écran de recherche transmet une destination au service de routage.
2. Le service retourne un itinéraire principal et, si possible, des alternatives.
3. Le comparateur applique les préférences : temps, distance, péages et détour maximal.
4. L'écran carte affiche les résultats avec leurs estimations et leurs limites.
5. Pendant la navigation, le suivi GPS compare la position au tracé.
6. En cas de déviation ou d'événement pertinent, l'application propose un recalcul.
7. L'utilisateur accepte ou refuse ; aucun changement silencieux.

## 5. Contrats à isoler

- `MapDataSource` : style, tuiles et données cartographiques.
- `GeocodingDataSource` : recherche et géocodage.
- `RoutingDataSource` : itinéraires et alternatives.
- `TrafficDataSource` : événements routiers disponibles.
- `LocationSource` : position et flux GPS.
- `OfflineRegionStore` : régions téléchargées et état local.

Les noms sont indicatifs ; les contrats seront définis dans le code après choix des bibliothèques.

## 6. Gestion des indisponibilités

Chaque source doit pouvoir signaler : indisponible, données périmées, couverture partielle ou erreur. L'application ne doit pas transformer une absence de données en absence d'incident.

## 7. Tests attendus

- Tests unitaires du comparateur d'itinéraires.
- Tests des limites de détour et préférences de péages.
- Tests des erreurs et données incomplètes.
- Tests d'intégration GPS et navigation sur appareils réels.
- Vérification de consommation réseau et batterie.
