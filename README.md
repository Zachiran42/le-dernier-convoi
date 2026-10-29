# Le Dernier Convoi

**Un train pour refuge. Une raison de continuer.**

Jeu solo de survie et de stratégie en 2D, conçu pour Android hors ligne. Le convoi traverse **cinq régions, de la Vallée des Cendres au Bastion de l’Aube** : choisir un embranchement, partir en expédition, ramener des ressources, aménager les wagons, puis reprendre la route.

**Version 0.2.0 — cinq régions, quarante étapes · Code et créations originales sous MIT**

- [Page du jeu et téléchargement Android](https://zachiran42.github.io/le-dernier-convoi/)
- [Jouer dans le navigateur](https://zachiran42.github.io/le-dernier-convoi/play/index.html?v=0.2.0)
- [APK 0.2.0 de développement signé](https://github.com/Zachiran42/le-dernier-convoi/releases/download/v0.2.0/le-dernier-convoi-0.2.0.apk)
- [Signaler un problème](https://github.com/Zachiran42/le-dernier-convoi/issues)

![Le train-refuge traverse un viaduc au milieu d’une vallée brumeuse.](art/key-art.png)

*Illustration de couverture originale, créée avec ImageGen. Il s’agit d’une illustration d’ambiance, pas d’une capture de jeu.*

## La grande traversée

La campagne compte **cinq régions de huit étapes chacune, soit quarante étapes au total**, avec un gardien à la fin de chaque région. Les réserves, l’état du train, les modules et l’équipage accompagnent le voyage jusqu’à son terme.

| Région | Étapes de campagne | Danger | Gardien |
|---|---|---|---|
| Vallée des Cendres | 1 à 8 | Braises sous la cendre | Gardien des Cendres |
| Marais de Verre | 9 à 16 | Flaques toxiques évitables | Veilleur de Verre |
| Désert des Antennes | 17 à 24 | Sol brûlant et besoin d’eau accru | Sentinelle des Antennes |
| Crêtes du Givre | 25 à 32 | Gel et coût en carburant accru | Brise-Givre |
| Bastion de l’Aube | 33 à 40 | Zones électriques | Vigie de l’Aube |

Les lieux, les cartes et les événements varient selon la région. Les dangers au sol peuvent être contournés ; ils infligent des dégâts lorsqu’on entre sur leur case. Le désert demande une eau supplémentaire au départ ; dans les crêtes, le coût annoncé des routes inclut un carburant supplémentaire.

Après chacun des quatre premiers gardiens, revenir au train ouvre une **escale de région** : acheter des fournitures avec de la ferraille, payer une réparation ou poursuivre gratuitement sans bonus. Le cinquième gardien termine la campagne.

- **Choisir la route :** comparer carburant, danger et ressources annoncées.
- **Aménager le train :** trois emplacements pour six modules — serre, citerne, atelier, blindage, infirmerie et dortoir.
- **Gérer les réserves :** carburant, rations, eau, ferraille, médicaments et munitions.
- **Veiller sur l’équipage :** Mira, Basile et Edda conservent leurs rôles et leurs blessures au fil des régions.
- **Explorer :** déplacements et actions au tour par tour sur une grille, combats, récupération et retour au point d’entrée.
- **Assumer le repli :** abandonner une expédition laisse le butin en cours derrière soi.
- **Reprendre une campagne :** sauvegarde locale, indépendante d’un compte et d’un serveur.

Les coûts et les effets chiffrés apparaissent dans le jeu. Le contenu et l’équilibre continuent d’évoluer avec les retours de jeu.

## Commandes

L’interface du jeu est conçue pour un écran en portrait, avec une résolution logique de 720 × 1280.

| Action | Téléphone | Clavier |
|---|---|---|
| Se déplacer | Toucher une direction ou une case | Flèches, ZQSD |
| Interagir | Commande Interagir | E |
| Attaquer | Commande Attaquer | Espace |
| Se soigner | Commande Soin | F |
| Attendre | Commande Attendre | Entrée |

Une attaque à distance consomme une munition. Rejoindre l’entrée valide le butin de l’expédition ; la commande de repli l’abandonne.

## Installer et jouer hors ligne

Télécharger l’APK depuis la page ou le dépôt, puis ouvrir le fichier sur Android. Android peut demander d’autoriser l’installation à l’application utilisée pour le télécharger. L’APK publié avec ce jalon est une version de développement signée.

Tous les fichiers nécessaires au jeu Android sont embarqués dans l’application. La page et la démo web nécessitent un chargement dans le navigateur. Le stockage de la démo dépend du navigateur et de ses réglages ; sa sauvegarde est indépendante de celle de l’APK.

La campagne est enregistrée localement dans `user://convoi-save.json`. Effacer les données de l’application ou du site peut supprimer la progression.

Les sauvegardes **0.1.0 sont reprises sans repartir à zéro** : réserves, équipage, modules et progression sont conservés. Une expédition en cours garde son terrain d’origine. Une ancienne victoire dans la vallée ouvre l’escale vers les Marais de Verre, avec un **ravitaillement gratuit de reprise utilisable une seule fois**, à choisir ou à laisser. Il permet de relancer le voyage sans réinitialiser le convoi. Cette offre concerne uniquement les anciennes victoires 0.1.0 ; les escales habituelles de la campagne 0.2.0 conservent leurs coûts. Une ancienne défaite conserve son état. La [Release 0.1.0](https://github.com/Zachiran42/le-dernier-convoi/releases/tag/v0.1.0) et son APK restent accessibles.

## Ouvrir le projet

Le projet utilise **Godot 4.7.2**, GDScript et le moteur de rendu **Compatibility**. Ouvrir `project.godot` dans Godot puis lancer le projet avec F5.

```sh
godot --headless --path . --editor --quit
```

La logique de campagne et d’expédition est séparée du rendu tactile. Le [document de conception](DESIGN.md) présente le périmètre, les choix et les invariants du jalon.

### Exports

Installer les modèles d’export correspondant à la version de Godot. Pour Android, configurer le JDK et le SDK Android dans les réglages de l’éditeur, puis utiliser le profil **Android** du projet. Le profil **Web** produit la démo servie depuis `docs/play/`.

```sh
# Depuis le dossier du projet, après configuration des modèles et outils :
mkdir -p build/android build/web-raw build/web-pages
touch build/.gdignore
godot --headless --path . --export-debug Android build/android/le-dernier-convoi.apk
godot --headless --path . --export-release Web build/web-raw/index.html
node tools/pack-web.cjs build/web-raw build/web-pages
```

Les chemins du SDK, les mots de passe et les clés de signature restent dans la configuration locale. Les caches `.godot/` et les fichiers de clés ne doivent pas être publiés.

## Organisation

```text
project.godot       Configuration du projet
scenes/            Scènes Godot
scripts/           Modèle et interface du jeu
art/               Illustration et ressources graphiques du projet
docs/              Page GitHub Pages et politique de confidentialité
docs/play/         Export web
docs/downloads/    Empreinte APK et lien vers la Release
```

GitHub Pages utilise la branche `main`, dossier `/docs`. Aucun serveur applicatif n’est requis pour héberger la page et la démo statiques.

## Conception et validation

Le jalon doit notamment conserver une campagne reprenable, des réserves cohérentes, des choix de route lisibles et des cartes d’expédition praticables. Les validations de génération, de sauvegarde, de combat et de progression accompagnent l’implémentation. Les vérifications sur navigateur et appareil restent complémentaires aux tests de logique.

Une modification du gameplay doit préserver ces invariants et mettre à jour les règles affichées au joueur. Les nouvelles fonctionnalités se construisent sur cette campagne et ses transitions entre régions.

## Confidentialité et licences

Aucun compte, aucune publicité, aucun achat intégré et aucun outil d’analyse de fréquentation ne sont intégrés au projet. Voir [la politique de confidentialité](docs/privacy.html).

Le code, les textes et les créations originales du projet sont proposés sous [licence MIT](LICENSE). La provenance et le prompt de l’illustration sont documentés dans [art/README.md](art/README.md).

Godot conserve sa [licence MIT et ses mentions tierces](https://godotengine.org/license/). Les modèles d’export, le SDK Android et les autres outils de compilation conservent leurs propres licences ; ils ne sont pas relicenciés par ce dépôt.

## Compiler et vérifier cette version

Les scripts et versions figées sont décrits dans [tools/BUILD.md](tools/BUILD.md). La CI valide les règles, les sauvegardes et les commandes avant de produire les exports Android et web. L’APK publié utilise ARM64, Android 7.0+ et ne demande aucune permission Internet. Les APK des artefacts CI utilisent une signature éphémère ; utilisez l’APK de la Release pour les mises à jour distribuées.

La démo web charge le même jeu Godot. Le transport du moteur WebAssembly est compressé pour GitHub Pages ; les modifications et empreintes sont documentées dans [docs/play/TRANSPORT.txt](docs/play/TRANSPORT.txt). Les textes complets des licences du moteur sont inclus dans le projet et dans les exports.


[Validation de la version](VALIDATION.md) · [Journal des versions](CHANGELOG.md)
