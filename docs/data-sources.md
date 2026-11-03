# Sources de données et stratégie de gratuité

## 1. Règle fondamentale

« Open source » ne signifie pas « service gratuit et illimité ». Il faut distinguer :
- le logiciel qui affiche ou traite les données ;
- les données cartographiques ;
- l'hébergement des tuiles ;
- le géocodage ;
- le moteur de routage ;
- les données de trafic et d'événements.

Chaque fournisseur possède ses propres conditions d'utilisation.

## 2. Cartographie — OpenStreetMap

OpenStreetMap fournit une base de données géographique ouverte, sous réserve de respecter l'ODbL et les obligations d'attribution.

Attention :
- les serveurs publics de tuiles OSM ne sont pas un CDN gratuit pour une application ;
- le téléchargement massif ou la mise en cache hors ligne de leurs tuiles peut être interdit par leur politique ;
- une vraie fonction hors ligne nécessite une source de tuiles autorisée, un fournisseur compatible ou une infrastructure maîtrisée.

MapLibre peut afficher des cartes compatibles, mais ne fournit pas les données lui-même.

## 3. Géocodage

Photon et Nominatim sont des solutions open source possibles. Leurs instances publiques ont des politiques d'usage et des limites. Elles ne doivent pas être considérées comme des API gratuites illimitées.

Pour une solution durable sans coût par requête, étudier un index local ou un service auto-hébergé, en tenant compte du stockage et de la complexité.

## 4. Routage

Valhalla et d'autres moteurs open source peuvent être étudiés. Le logiciel peut être gratuit, mais construire, mettre à jour et héberger les graphes routiers exige des ressources.

Prototype obligatoire avant de retenir une solution :
- calcul d'un trajet ;
- alternatives ;
- contraintes de péages ;
- fonctionnement hors ligne ;
- taille des données régionales ;
- temps de calcul sur téléphone.

## 5. Trafic et événements

Étudier les jeux de données ouverts français, notamment les portails publics de transport et les données routières nationales ou locales.

La couverture, la fraîcheur, les formats et les licences varient selon la source et le territoire. Il ne faut pas promettre une vision exhaustive du trafic en direct.

Pour chaque événement, conserver si possible :
- source ;
- type d'événement ;
- position ou segment concerné ;
- date de publication ;
- date de dernière mise à jour ;
- date de fin prévue, si fournie ;
- niveau de confiance ou état de fraîcheur.

## 6. Cartes hors ligne

La fonction hors ligne doit être conçue autour de régions explicitement sélectionnées. Il faut vérifier les droits de téléchargement, le volume, les mises à jour et le stockage avant de choisir un fournisseur.

Ne jamais aspirer les tuiles d'un service public sans autorisation.

## 7. Tableau de validation

| Domaine | Piste | Point à valider |
|---|---|---|
| Carte | OpenStreetMap + rendu MapLibre | Source de tuiles et attribution |
| Recherche | Photon / Nominatim | Politique de l'instance ou index local |
| Routage | Valhalla ou alternative | Déploiement, alternatives, offline |
| Événements | Données publiques françaises | Couverture, fraîcheur, licence |
| Hors ligne | Paquets régionaux | Source autorisée, stockage, mises à jour |

Aucune source n'est considérée comme définitivement choisie avant les prototypes.
