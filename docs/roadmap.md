# Feuille de route

## Phase 0 — Cadrage (en cours)

- [x] Créer le dépôt.
- [x] Définir le périmètre V1.
- [x] Documenter les contraintes de gratuité.
- [ ] Valider les sources cartographiques et leurs licences.
- [ ] Comparer les moteurs de routage.
- [ ] Définir le périmètre géographique du premier prototype.

## Phase 1 — Prototype technique

- [ ] Initialiser un vrai projet Flutter.
- [ ] Afficher une carte sur Android.
- [ ] Obtenir et afficher la position GPS.
- [ ] Tester une recherche de destination.
- [ ] Calculer un premier itinéraire.
- [ ] Mesurer taille, latence, batterie et consommation réseau.

**Sortie attendue :** une application de test qui affiche une carte, une position et un trajet simple.

## Phase 2 — Comparateur d'itinéraires

- [ ] Afficher plusieurs alternatives.
- [ ] Comparer durée et distance.
- [ ] Intégrer les informations de péage disponibles.
- [ ] Appliquer le détour maximal de 15 km.
- [ ] Expliquer les données manquantes.

**Sortie attendue :** l'utilisateur comprend pourquoi une alternative est proposée.

## Phase 3 — Navigation

- [ ] Suivi GPS pendant un trajet.
- [ ] Détection de déviation.
- [ ] Proposition de recalcul.
- [ ] Confirmation obligatoire avant changement.
- [ ] Gestion des pertes GPS et réseau.

## Phase 4 — Événements routiers

- [ ] Identifier les sources ouvertes réellement exploitables.
- [ ] Importer et normaliser les événements.
- [ ] Afficher source et horodatage.
- [ ] Filtrer les événements trop anciens.
- [ ] Ne pas confondre absence d'information et route dégagée.

## Phase 5 — Hors ligne et stabilisation

- [ ] Prototype de téléchargement régional autorisé.
- [ ] Recherche et routage hors ligne si faisables.
- [ ] Mise à jour des données locales.
- [ ] Tests terrain.
- [ ] Mesures batterie, mémoire et stockage.
- [ ] Préparer une version bêta privée.

## Règle de progression

Ne pas développer toutes les fonctionnalités en même temps. Chaque phase doit produire une version testable avant d'ajouter la suivante.
