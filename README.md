# Route Optimizer

Application mobile de navigation GPS indépendante, conçue pour comparer des itinéraires et aider à choisir un trajet selon le temps, le coût et les conditions de circulation disponibles.

> **État du projet : cadrage / documentation.** Le dépôt ne contient pas encore de code applicatif. Cette structure prépare le développement sans créer artificiellement un projet Flutter incomplet.

## Objectifs

- Afficher une carte interactive et la position GPS.
- Rechercher une adresse ou un lieu.
- Calculer un itinéraire et proposer des alternatives.
- Comparer durée, distance et coût estimé, notamment les péages.
- Suivre un trajet avec progression GPS.
- Signaler les événements routiers uniquement à partir de sources ouvertes réellement disponibles.
- Proposer un changement d'itinéraire, puis attendre la confirmation de l'utilisateur.

## Principes de la V1

- Gratuité : aucune API payante, aucun abonnement, aucune publicité.
- Pas de compte utilisateur, de Firebase, de partenariat ni de signalement communautaire.
- Pas de guidage vocal.
- Détour supplémentaire maximal configurable, avec une limite initiale de **15 km**.
- Comparaison équilibrée : temps, distance, péages et qualité des données.
- Aucune modification automatique de l'itinéraire sans accord explicite.

## Documentation

| Fichier | Rôle |
|---|---|
| [Cahier des charges](docs/specification.md) | Fonctionnalités et limites de la V1 |
| [Architecture](docs/architecture.md) | Organisation technique cible |
| [Sources de données](docs/data-sources.md) | Cartographie, routage et trafic |
| [Feuille de route](docs/roadmap.md) | Étapes de réalisation |
| [Décisions techniques](docs/decisions.md) | Choix actés et raisons |

## Structure prévue

```text
route-optimizer/
├── README.md
└── docs/
    ├── specification.md
    ├── architecture.md
    ├── data-sources.md
    ├── roadmap.md
    └── decisions.md
```

Les dossiers et fichiers Flutter (`lib/`, `test/`, `android/`, `pubspec.yaml`) seront ajoutés lors de l'initialisation réelle de l'application, afin de conserver un projet compilable.

## Statut

**Phase 0 — cadrage.** Les choix d'architecture et les sources de données doivent être validés avant l'implémentation. La disponibilité des données trafic varie selon les territoires et ne doit jamais être présentée comme exhaustive.

## Licence

À définir avant toute publication ou redistribution. Les licences des bibliothèques et jeux de données utilisés devront être respectées et documentées.
