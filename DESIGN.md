# Le Dernier Convoi — conception du premier jalon

## Intention

Le refuge est un train qui continue d’avancer. Les expéditions offrent les ressources nécessaires au prochain départ ; les choix effectués dans le convoi modifient ce que le joueur peut tenter sur la route.

La proposition initiale décrivait un jeu 2D mêlant survie, gestion d’un train modulaire, expéditions et événements à conséquences. La version 0.1.0 en développe une première boucle complète : **la Vallée des Cendres, huit étapes et une menace finale**.

Ce document décrit les intentions et les règles visibles. Les valeurs numériques de référence appartiennent au modèle du jeu ; une modification des coûts ou des effets doit rester cohérente avec les informations affichées dans l’interface.

## Périmètre de la version 0.1.0

| Élément | Périmètre |
|---|---|
| Plateforme principale | Application Android solo, contenu embarqué et jeu hors ligne |
| Accès web | Export Godot de la même première région, servi statiquement |
| Format | 2D, interface en portrait, résolution logique de 720 × 1280 |
| Région | Vallée des Cendres |
| Structure | Huit étapes, choix de trajet et menace finale |
| Aménagement | Trois emplacements de wagons, six modules disponibles |
| Expéditions | Grille tactique, déplacement, interaction, combat, soin et attente |
| Progression | Réserves, état du convoi, étapes et résultats d’expédition |
| Reprise | Sauvegarde locale de la campagne et de la phase en cours |
| Distribution | Dépôt public, page par application, code et créations originales sous MIT |

## Les décisions qui font le jeu

### 1. Une route répond à un besoin et crée un coût

Avant le départ, le joueur dispose d’informations sur le carburant demandé, le danger et les ressources possibles. Le choix doit rester compréhensible sans connaître les valeurs internes du modèle.

Un trajet intéressant n’est pas seulement celui qui rapporte le plus. Il dépend des réserves actuelles, de l’état du convoi et de ce que le joueur prévoit de faire à l’étape suivante.

### 2. Les emplacements créent une priorité

Trois emplacements obligent à répartir les rôles du convoi entre six modules :

| Module | Intention de jeu |
|---|---|
| Serre | Autonomie alimentaire et gestion des rations |
| Citerne | Autonomie en eau et réserves du voyage |
| Atelier | Entretien et maintien du convoi |
| Blindage | Protection sur les trajets dangereux |
| Infirmerie | Soins et conséquences des blessures |
| Dortoir | Conditions de vie à bord |

L’interface doit indiquer les coûts, les effets et les conditions avant validation d’un aménagement. Le joueur doit pouvoir comprendre pourquoi un module est utile à sa campagne actuelle.

### 3. Le retour fait partie de l’expédition

Sur une grille, le joueur se déplace, examine les occasions, interagit, attaque, se soigne ou attend. Le tour par tour permet de décider au toucher sans imposer une précision de déplacement en temps réel.

Les ressources récupérées au cours de la sortie restent un butin d’expédition. Revenir au point d’entrée valide le retour ; un repli volontaire abandonne le butin en cours. Cette séparation doit être lisible dans l’interface et dans la sauvegarde.

Le tir à distance consomme des munitions. Les soins utilisent les ressources adaptées. Une action refusée doit donner une raison compréhensible et préserver un état cohérent.

## Boucle complète

1. Lire l’état du train, les réserves et les routes proposées.
2. Choisir un trajet en connaissant ses coûts annoncés.
3. Résoudre le voyage et ses conséquences.
4. Explorer l’étape et décider du niveau de risque acceptable.
5. Revenir ou se replier ; appliquer le résultat à la campagne.
6. Répartir les ressources, aménager le convoi et préparer l’étape suivante.
7. Franchir les huit étapes puis la menace finale, ou atteindre une fin de campagne.

## Réserves

Les six ressources du jalon sont le **carburant**, les **rations**, l’**eau**, la **ferraille**, les **médicaments** et les **munitions**.

Les coûts sont vérifiés avant application. Les compteurs doivent conserver des valeurs finies, non négatives et cohérentes. Les résultats d’une interaction ou d’une fin d’expédition sont appliqués une seule fois.

## Interface

La direction graphique associe charbon, bleu pétrole, verts sourds et ambre. L’illustration du train établit l’ambiance du projet ; la lisibilité des réserves, des actions et du terrain prime dans le jeu.

L’interface présente les décisions par phase : accueil, convoi, carte de route, expédition, résultat et fin de campagne. Les informations nécessaires à une décision doivent être visibles avant son engagement.

Les actions principales sont accessibles par commandes tactiles. Le clavier fournit une autre entrée vers les mêmes actions : flèches ou ZQSD pour se déplacer, E pour interagir, Espace pour attaquer, F pour se soigner et Entrée pour attendre.

## Sauvegarde et reprise

La sauvegarde locale se trouve à `user://convoi-save.json`. Elle doit couvrir les informations nécessaires à une reprise cohérente : campagne, étape, phase, réserves, modules, expédition en cours et état du hasard utilisé par le modèle.

Une sauvegarde invalide ne doit pas corrompre une campagne valide ni empêcher de commencer un voyage. Les entrées tactiles transitoires ne doivent pas rester actives après une reprise ou une interruption de l’application.

La sauvegarde web dépend du stockage persistant fourni par le navigateur. Elle reste distincte de celle de l’application Android.

## Invariants à valider

- La génération donne accès aux éléments nécessaires au déroulement d’une expédition.
- Les commandes tactiles et clavier appellent les mêmes règles de jeu.
- Les coûts sont contrôlés avant de modifier les réserves.
- Une récompense, une dépense ou une fin n’est appliquée qu’une fois.
- L’abandon d’une sortie ne valide pas son butin.
- La sauvegarde et la reprise préservent la campagne et la phase en cours.
- Les données incohérentes sont rejetées proprement.
- Les victoires et les défaites conduisent à une fin de campagne lisible.
- Une application Android installée peut effectuer toute la traversée sans réseau.

Les tests automatisés vérifient le modèle. Les essais du rendu, du toucher, de la reprise et des exports complètent cette validation sur les plateformes visées.

## Évolution

La première région est la base de travail du projet. L’équilibrage des trajets, le rythme des expéditions, l’utilité des modules et la clarté des conséquences guident les améliorations du jalon. Les extensions de contenu et les nouveaux systèmes feront l’objet de décisions de conception séparées.
