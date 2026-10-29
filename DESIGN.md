# Le Dernier Convoi — conception de la campagne 0.2.0

## Intention

Le refuge est un train qui continue d’avancer. Les expéditions offrent les ressources nécessaires au prochain départ ; les choix effectués dans le convoi modifient ce que le joueur peut tenter sur la route.

La version 0.1.0 posait une première boucle complète dans la Vallée des Cendres. La version 0.2.0 l’étend à **cinq régions au total, huit étapes par région et quarante étapes de campagne**, avec un gardien par région. La vallée reste la première des cinq régions.

Ce document décrit les intentions et les règles visibles. Les valeurs numériques de référence appartiennent au modèle du jeu ; une modification des coûts ou des effets doit rester cohérente avec les informations affichées dans l’interface.

## Périmètre de la version 0.2.0

| Élément | Périmètre |
|---|---|
| Plateforme principale | Application Android solo, contenu embarqué et jeu hors ligne |
| Accès web | Export Godot de la même campagne de cinq régions, servi statiquement |
| Format | 2D, interface en portrait, résolution logique de 720 × 1280 |
| Régions | Vallée des Cendres, Marais de Verre, Désert des Antennes, Crêtes du Givre, Bastion de l’Aube |
| Structure | Quarante étapes : huit dans chaque région, cinq gardiens au total |
| Transitions | Quatre escales avec choix avant de poursuivre dans la région suivante |
| Aménagement | Trois emplacements de wagons, six modules disponibles |
| Expéditions | Grille tactique, déplacement, interaction, combat, soin et attente |
| Progression | Réserves, état du convoi, étapes et résultats d’expédition |
| Reprise | Sauvegarde locale de la campagne et de la phase en cours |
| Distribution | Dépôt public, page par application, code et créations originales sous MIT |

## Les cinq régions

| Région | Étapes globales | Terrain et contrainte de trajet | Menace de fin de région |
|---|---|---|---|
| Vallée des Cendres | 1–8 | Brume, cendres et braises au sol | Gardien des Cendres |
| Marais de Verre | 9–16 | Flaques toxiques évitables | Veilleur de Verre |
| Désert des Antennes | 17–24 | Tôle brûlante ; une eau supplémentaire au départ | Sentinelle des Antennes |
| Crêtes du Givre | 25–32 | Gel ; un carburant supplémentaire déjà inclus dans le coût annoncé | Brise-Givre |
| Bastion de l’Aube | 33–40 | Zones d’arcs électriques | Vigie de l’Aube |

Les noms de lieux, les cartes et les événements proposent des variantes régionales. Les dangers sont des cases visibles lors de l’exploration : leurs dégâts s’appliquent lorsqu’un survivant entre sur une case dangereuse. Ils peuvent être contournés. Rester sur place ou changer de tour n’ajoute pas de dégâts de terrain à lui seul.

Après un gardien, le retour au train clôt l’expédition. Pour les quatre premières régions, une escale propose trois issues à usage unique : payer des fournitures en ferraille, payer une réparation en ferraille ou poursuivre gratuitement sans bonus. Ce choix précède le prochain départ. Les ressources, la coque, les modules et l’équipage ne sont pas réinitialisés.

La victoire sur la Vigie de l’Aube et le retour au train terminent la quarantième étape et la campagne. Il n’existe pas de sixième région dans cette version.

## Les décisions qui font le jeu

### 1. Une route répond à un besoin et crée un coût

Avant le départ, le joueur dispose d’informations sur le carburant demandé, le danger et les ressources possibles. Le choix doit rester compréhensible sans connaître les valeurs internes du modèle.

Un trajet intéressant n’est pas seulement celui qui rapporte le plus. Il dépend des réserves actuelles, de l’état du convoi et de ce que le joueur prévoit de faire à l’étape suivante.

### 2. Les emplacements créent une priorité

Trois emplacements obligent à répartir les rôles du convoi entre six modules :

| Module | Intention de jeu |
|---|---|
| Serre | Autonomie alimentaire et gestion des rations |
| Citerne | Capacité de carburant et réserves du voyage |
| Atelier | Entretien et maintien du convoi |
| Blindage | Protection sur les trajets dangereux |
| Infirmerie | Soins et conséquences des blessures |
| Dortoir | Conditions de vie à bord |

L’interface doit indiquer les coûts, les effets et les conditions avant validation d’un aménagement. Le joueur doit pouvoir comprendre pourquoi un module est utile à sa campagne actuelle.

Mira, Basile et Edda forment l’équipage initial. Leurs rôles, leurs blessures et les éventuels changements d’équipage accompagnent les cinq régions ; une transition ne crée pas un nouvel équipage.

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
7. Franchir le gardien de la huitième étape, revenir au train et choisir l’escale avant la région suivante.
8. Répéter la traversée jusqu’au cinquième gardien, au terme des quarante étapes, ou atteindre une défaite.

## Réserves

Les six ressources du jalon sont le **carburant**, les **rations**, l’**eau**, la **ferraille**, les **médicaments** et les **munitions**.

Les coûts sont vérifiés avant application. Les compteurs doivent conserver des valeurs finies, non négatives et cohérentes. Les résultats d’une interaction ou d’une fin d’expédition sont appliqués une seule fois.

## Interface

La direction graphique associe charbon, bleu pétrole, verts sourds et ambre. L’illustration du train établit l’ambiance du projet ; la lisibilité des réserves, des actions et du terrain prime dans le jeu.

L’interface présente les décisions par phase : accueil, convoi, carte de route, expédition, résultat, escale de région et fin de campagne. Le suivi distingue la région sur cinq, la halte sur huit et la progression globale sur quarante. L’atlas indique les régions traversées, la région actuelle et celles qui restent à atteindre. Les informations nécessaires à une décision doivent être visibles avant son engagement.

Les actions principales sont accessibles par commandes tactiles. Le clavier fournit une autre entrée vers les mêmes actions : flèches ou ZQSD pour se déplacer, E pour interagir, Espace pour attaquer, F pour se soigner et Entrée pour attendre.

## Sauvegarde et reprise

La sauvegarde locale se trouve à `user://convoi-save.json`. Elle couvre les informations nécessaires à une reprise cohérente : campagne, région, étape locale et globale, phase, réserves, modules, expédition en cours, dangers déjà générés et état du hasard utilisé par le modèle.

Les sauvegardes 0.1.0 sont migrées sans remise à zéro des réserves, de l’équipage, des modules ou de la progression. Une ancienne expédition reste dans la vallée avec son terrain initial, sans ajout rétroactif de nouveaux dangers. Une ancienne victoire ouvre l’escale d’entrée des Marais de Verre ; une ancienne défaite reste une défaite. Les escales en cours font partie de l’état sauvegardé.

Pour une **ancienne victoire 0.1.0 uniquement**, cette première escale propose un ravitaillement gratuit de reprise, utilisable une fois, ou la possibilité de passer. L’offre ajoute six carburants, six rations et quatre eaux, répare vingt-quatre points de coque et soigne douze PV du survivant actif, dans les limites habituelles. Elle ne remplit pas toutes les réserves et ne remplace ni le train ni l’équipage. Elle évite qu’une ancienne victoire terminée avec un réservoir vide soit condamnée dès la reprise. Les quatre escales ordinaires d’une nouvelle campagne 0.2.0 gardent leurs offres payantes et leur option de passage gratuit.

Une sauvegarde invalide ne doit pas corrompre une campagne valide ni empêcher de commencer un voyage. Les entrées tactiles transitoires ne doivent pas rester actives après une reprise ou une interruption de l’application.

La sauvegarde web dépend du stockage persistant fourni par le navigateur. Elle reste distincte de celle de l’application Android.

## Invariants à valider

- La génération donne accès aux éléments nécessaires au déroulement d’une expédition.
- Les commandes tactiles et clavier appellent les mêmes règles de jeu.
- Les coûts sont contrôlés avant de modifier les réserves.
- Une récompense, une dépense ou une fin n’est appliquée qu’une fois.
- L’abandon d’une sortie ne valide pas son butin.
- La sauvegarde et la reprise préservent la campagne et la phase en cours.
- Les migrations 0.1.0 conservent la progression et les ressources existantes.
- L’offre de reprise d’une ancienne victoire n’est consommable qu’une fois et ne s’applique jamais à une nouvelle campagne 0.2.0.
- Les transitions régionales n’appliquent leur récompense ou leur coût qu’une fois.
- La campagne contient exactement cinq régions de huit étapes, et une menace de fin par région.
- Les terrains dangereux restent contournables et infligent leurs dégâts à l’entrée sur la case.
- Les données incohérentes sont rejetées proprement.
- Les victoires et les défaites conduisent à une fin de campagne lisible.
- Une application Android installée peut effectuer toute la traversée sans réseau.

Les tests automatisés vérifient le modèle. Les essais du rendu, du toucher, de la reprise et des exports complètent cette validation sur les plateformes visées.

## Évolution

Les cinq régions forment la campagne de référence. L’équilibrage des trajets, le rythme des expéditions, l’utilité des modules et la clarté des conséquences guident les améliorations. Les extensions de contenu et les nouveaux systèmes feront l’objet de décisions de conception séparées.
