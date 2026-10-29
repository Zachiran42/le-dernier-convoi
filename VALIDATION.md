# Validation — Le Dernier Convoi 0.1.0

Version du 29 octobre 2026. Moteur officiel Godot 4.7.2 stable, `ed1daf0bf`.

## Règles et sauvegardes

18 scénarios de tests réussissent : génération déterministe, reprise JSON et hasard, rejets transactionnels des sauvegardes corrompues, dépenses et remplacement des wagons, recettes et rôles, vivres, soins, visibilité, attaques annoncées, munitions, butin, repli, recrutement et fins de partie.

La visibilité est symétrique entre le héros et les ennemis et respecte les coins fermés. Une défaite par carburant tient compte des possibilités légales d’allègement, de changement de pilote et de fabrication.

17 campagnes complètes ont été simulées par actions légales jusqu’à la victoire : huit graines de base, puis trois graines avec chacun des modules de départ serre, blindage et atelier. L’attente passive mène à la défaite.

## Interface et chaîne de compilation

125 assertions d’intégration valident la sauvegarde et la reprise, les protections des fenêtres modales, les commandes clavier, les coordonnées tactiles, les coûts affichés de fabrication et les limites des boutons. Les actions tactiques offrent une cible d’au moins 44 pixels de haut pour un écran large de 360 pixels.

4 tests supplémentaires vérifient les empreintes de téléchargement, l’extraction contrôlée, le rejet des archives corrompues et la détection des erreurs Godot malgré un code de sortie nul.

Les exports Android et Web ont réussi localement sans erreur de script. L’écran d’accueil, la gestion du train, la confirmation de construction, les routes, un événement et le départ en expédition ont été contrôlés dans le navigateur.

## APK et ressources

L’APK signé 0.1.0 utilise ARM64, minSdk24 et targetSdk36. Sa signature a été vérifiée. Il ne demande aucune permission, notamment aucune permission Internet. Le code exporté de l’interface, du modèle et les textes de licence sont identiques dans l’APK et le pack Web. Aucun export imbriqué, cache d’éditeur, test ni clé privée n’est embarqué dans les ressources du jeu.

L’empreinte SHA-256 de l’APK est publiée dans [docs/downloads](docs/downloads/le-dernier-convoi-0.1.0.apk.sha256) et avec la Release.

## Limites

Aucun téléphone Android physique n’a été utilisé. Le confort tactile, le comportement en mode avion et les performances restent à confirmer sur un appareil réel. La démo requiert WebGL2 et DecompressionStream pour son premier chargement. Les sauvegardes du navigateur et de l’APK sont indépendantes.

La CI du dépôt reconstruit les deux exports et exécute les tests à chaque modification de main. Ses résultats sont consultables dans l’onglet Actions ; ce rapport décrit les vérifications locales de la version publiée.
