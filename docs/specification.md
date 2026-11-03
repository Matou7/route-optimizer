# Cahier des charges — Route Optimizer

## 1. Vision

Route Optimizer est une application mobile GPS qui aide à choisir un itinéraire en fonction de plusieurs critères, plutôt que de privilégier uniquement la durée estimée.

La V1 vise un outil personnel, sobre, fiable et sans frais récurrents imposés par des services propriétaires.

## 2. Périmètre fonctionnel V1

### Carte et position
- Carte interactive.
- Demande de permission de localisation au moment utile.
- Affichage de la position et suivi GPS pendant un trajet.
- Gestion claire des permissions refusées et du signal GPS indisponible.

### Recherche et itinéraires
- Recherche d'adresse ou de lieu.
- Calcul d'un trajet vers une destination.
- Présentation d'un itinéraire principal et d'alternatives lorsqu'elles existent.
- Affichage de la distance et de la durée estimée.
- Comparaison des péages et du coût estimé lorsque les données le permettent.

### Navigation
- Progression sur le trajet.
- Détection d'un écart significatif à l'itinéraire.
- Recalcul proposé à l'utilisateur.
- Aucun changement d'itinéraire sans confirmation explicite.

### Radar anticipatif
- Exploitation de données ouvertes d'événements routiers, travaux ou perturbations lorsque disponibles.
- Indication de la source, de l'horodatage et de la couverture.
- Pas de promesse de trafic exhaustif ou temps réel sur tout le réseau.

### Paramètres
- Détour supplémentaire maximal : 15 km par défaut.
- Préférences de péages et compromis temps/coût.
- Réglages simples, sans compte utilisateur.

## 3. Hors périmètre V1

- Guidage vocal.
- Comptes et synchronisation cloud.
- Firebase.
- Publicité, abonnement ou API payante.
- Signalements communautaires.
- Partenariats commerciaux.
- Promesse de couverture trafic universelle.

## 4. Principes UX

- Interface lisible en conduite, avec interactions minimales.
- Les limites des données doivent être visibles.
- Toujours distinguer estimation, donnée observée et information indisponible.
- Toute décision qui modifie le trajet demande une validation utilisateur.

## 5. Critères d'acceptation

- L'utilisateur peut saisir une destination et obtenir un itinéraire lorsque le moteur et les données sont disponibles.
- Les alternatives sont comparées avec des critères compréhensibles.
- Le plafond de détour de 15 km est respecté lors du filtrage des alternatives.
- Les péages inconnus sont indiqués comme inconnus, jamais inventés.
- Une suggestion de changement ne modifie pas le trajet avant validation.
- L'application reste utilisable sans compte.
- Les erreurs réseau, GPS et données indisponibles sont traitées explicitement.

## 6. Contraintes non fonctionnelles

- Coût d'exploitation cible : 0 € pour le développement et l'usage personnel, sous réserve des limites des infrastructures publiques.
- Architecture modulaire pour pouvoir remplacer une source.
- Respect des licences et politiques d'utilisation des données.
- Pas de téléchargement massif de tuiles depuis des serveurs publics non prévus pour cet usage.
