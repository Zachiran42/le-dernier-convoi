# Validation — Le Dernier Convoi 0.2.0

Version du 29 octobre 2026. Moteur officiel Godot 4.7.2 stable, ed1daf0bf.

## Campagne et sauvegardes

27 scénarios de règles passent : les contrôles existants de génération déterministe, visibilité, combat, réserves, modules et sauvegardes, puis les cinq régions, les besoins chiffrés au départ, les terrains dangereux évitables, les cinq gardiens, les quatre escales et la victoire après la quarantième étape. Les dégâts de terrain surviennent à l’entrée ; attendre sur une case ne les répète pas. Les ennemis utilisent aussi leur portée régionale après déplacement.

17 campagnes complètes de quarante étapes ont été simulées par actions légales : huit graines sans wagon de départ, puis trois graines avec chacun des modules serre, blindage et atelier. Le bot gère les réserves, fabrique, répare ou recycle ses modules si nécessaire ; aucun plein ni soin gratuit n’est injecté dans ces simulations. Cela vérifie la possibilité de gagner, sans garantir que chaque stratégie réussira.

Cinq vrais formats de sauvegarde de la version publiée 0.1.0 sont lus dans les tests : base, choix de trajet, expédition, victoire et défaite. Une ancienne victoire ouvre les Marais de Verre et une offre facultative unique de reprise. L’offre n’est jamais régénérée après utilisation. Les sauvegardes corrompues sont refusées sans modifier la partie actuelle, notamment une fausse version 0.1 au-delà de son ancienne limite de huit étapes.

## Interface et compilation

402 assertions d’intégration passent : sauvegarde et reprise, protections modales, commandes clavier/tactiles, coûts de fabrication, cinq palettes, atlas sans saut de progression, dangers visibles, titres longs, escales et disponibilité du recrutement. Les commandes tactiques et les cinq boutons de l’atlas font au moins 88 unités logiques de haut, soit 44 pixels pour un écran de 360 pixels de large.

Quatre tests de chaîne de compilation passent : empreintes officielles, extraction contrôlée, archives corrompues et erreurs Godot détectées même avec code de sortie nul. Les exports Web et Android réussissent sans erreur de script.

Le rendu de l’atlas a été contrôlé dans l’export final. Un harness privé hors dépôt a permis de voir le Bastion et ses dangers, d’essayer les quatre directions et de vérifier le brouillard sur un viewport de 390 × 844, sans lire ni écrire de sauvegarde publique. La vitrine et son atlas sont contrôlés à largeur mobile et bureau. Le harness QA ne fait partie d’aucun fichier publié.

## APK et ressources

APK 0.2.0, versionCode2, ARM64, minSdk24 et targetSdk36. La signature est vérifiée et son certificat est identique à celui de l’APK 0.1.0. Aucune permission n’est demandée, notamment aucune permission Internet. Les scripts compilés de l’interface et du modèle et les licences sont identiques entre Android et Web. Aucun cache d’éditeur, test, outil, export imbriqué ni clé privée n’est embarqué.

SHA-256 APK : 3e3bcec400d7bdd92940a0ad412fdcbef8eac9b81e9d6f0e46b7da9287ed002c

L’empreinte accompagne l’APK dans la Release et dans docs/downloads. Le pack Web porte un nom contenant son empreinte pour éviter la réutilisation du contenu 0.1 en cache.

## Limites

Aucun téléphone Android physique n’a été utilisé. Le confort tactile, le mode avion et les performances restent à confirmer sur appareil réel. La démo requiert WebGL2 et DecompressionStream pour son premier chargement ; ses sauvegardes sont indépendantes de celles de l’APK.

La CI du dépôt reconstruit les deux exports et exécute les tests à chaque modification de main. Ses résultats sont consultables dans Actions ; ce rapport décrit les vérifications locales de cette version.
