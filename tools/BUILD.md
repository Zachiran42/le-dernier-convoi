# Builds Android et Web

La CI utilise Godot standard **4.7.2 stable**, commit `ed1daf0bf`, Python 3.13, Node 24 et JDK 17. Les actions GitHub sont epinglees par commit. Les noms de presets du projet doivent etre `Android` et `Web`.

`fetch-godot.py` interroge la release officielle, compare les SHA256 de son API aux valeurs verrouillees, telecharge et verifie les archives entieres, puis extrait seulement l'editeur et cinq fichiers Android/Web. Chaque lecture ZIP valide son CRC32. Le TPZ complet pese environ 1,28 Go ; il est conserve sous `build/toolchain/godot/downloads` pour une reutilisation locale verifiee. Aucun paquet Python tiers n'est necessaire.

Le fichier `_sc_` adjacent a l'editeur isole les preferences dans `editor_data`. Les autres caches, logs, exports et la cle de test sont places sous `build/`. Le fichier `build/.gdignore` empeche l'import des outils et des exports dans le jeu. Le SDK CI installe Platform 35 et 36, Platform-Tools et Build-Tools 35.0.1 ; l'APK precompile Godot utilise targetSdk36. Cette voie n'utilise pas Gradle, NDK ou CMake.

`run-godot.py` exige un code de sortie nul **et** l'absence de lignes `SCRIPT ERROR:` ou `ERROR:`. Godot peut autrement signaler une erreur de parsing tout en retournant zero. Les sorties attendues doivent exister et etre non vides.

La CI produit un APK **release ARM64**, un export Web brut et une variante Web pour GitHub Pages. Les archives de sortie et leurs licences sont disponibles dans les artefacts Actions ; la CI ne publie ni commit ni release automatiquement.

La cle CI est creee pour chaque execution et n'est jamais televersee. Les APK issus de deux executions CI ont donc des signatures differentes : desinstaller la precedente version de test avant d'installer une autre. Pour une distribution avec mises a jour, utiliser une cle de publication stable conservee hors du depot. La version release locale du script Windows reutilise sa cle sous `build/signing/local.keystore`.

## Reconstruction Windows

Installer Python 3.13, Node 24, JDK 17 et le SDK Android, puis executer depuis le depot :

```powershell
./tools/rebuild-windows.ps1 -JavaSdk 'C:/chemin/jdk-17' -AndroidSdk 'C:/chemin/android-sdk'
```

Pour reutiliser un editeur portable deja installe, ajouter `-GodotExe 'C:/chemin/Godot_v4.7.2-stable_win64_console.exe'`. Les variables d'environnement sont restaurees a la fin ; les preferences de l'editeur fourni sont configurees en mode portable.

## Conditionnement Web

Le moteur WASM officiel fait environ 39,5 Mo, au-dela de la limite de fichier de l'upload GitHub par navigateur. Le script suivant conserve l'export original et prepare un moteur gzip d'environ 10,2 Mo :

```sh
node tools/pack-web.cjs build/web-raw build/web-pages
```

Il verifie le SHA256 du WASM officiel et le motif unique de `Engine.load`, puis remplace uniquement son transport par une `Response` decompressee avec `DecompressionStream('gzip')`. `Engine.init` et `instantiateWasm` restent ceux de Godot. Le JavaScript modifie contient une notice ; les licences moteur et tiers sont jointes. Le serveur doit servir `index.wasm.gz` sans `Content-Encoding: gzip`, comme GitHub Pages. Le navigateur doit prendre en charge DecompressionStream. Aucun service worker, en-tete COOP/COEP ou remplacement global de fetch n'est requis.

Les notices `LICENSE`, `GODOT_LICENSE.txt`, `GODOT_THIRD_PARTY_LICENSES.txt` doivent exister a la racine et etre incluses dans la distribution. Les fichiers texte utilises dans les credits du jeu doivent aussi etre inclus par le preset d'export.

Sources officielles : [release Godot](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable), [export Android](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html), [export Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html), [mode portable](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html#self-contained-mode).

Depuis 0.2.0, le conditionnement donne aussi au pack de jeu un nom `index.<sha256 court>.pck` et le configure avec l’option publique Godot `mainPack`. La copie canonique `index.pck` reste identique. Chaque nouvelle compilation change donc l’URL du contenu lorsque ses octets changent, sans modifier le moteur.
