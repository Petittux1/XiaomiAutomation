# XiaomiAutomation

[中文](README.md) · [English](README.en.md) · [Русский](README.ru.md)

Un module d'automatisation root KSU / Magisk pour le **Xiaomi 17 Pro / HyperOS 4**. Il fournit une planification multi-profils, l'enregistrement et la relecture des gestes de n'importe quelle application, et conserve la tâche intégrée d'arrosage quotidien d'ICBC.

Il fonctionne par **contrôle root direct** (`screencap` / `getevent` / `sendevent`) — sans service d'accessibilité, sans Xposed, sans hook et sans injection `input`.

> ⚠️ **Avertissement**
> - Ce projet est destiné uniquement à l'étude technique. Il n'a aucun lien avec la Banque industrielle et commerciale de Chine et ne bénéficie d'aucune autorisation de celle-ci.
> - L'automatisation peut enfreindre les conditions d'utilisation d'une application ou la législation locale. Évaluez les risques vous-même.
> - Vous assumez toutes les conséquences de l'utilisation de ce projet. L'auteur et les contributeurs déclinent toute responsabilité.
> - Ne l'utilisez pas à des fins commerciales, pour du traitement en masse ou à but lucratif. Si la fonction concernée est interdite par une application ou un opérateur, arrêtez de l'utiliser et désinstallez-le immédiatement.
> - Il touche à des fonctions de compte ; les risques vous incombent. Déconseillé sur des comptes importants ou réels.

## Fonctionnalités

- Un profil intégré « Arrosage ICBC quotidien » s'exécute chaque jour à `07:30` par défaut ; il peut aussi être déclenché manuellement, ainsi qu'à la première ouverture d'ICBC de la journée.
- Planification indépendante par profil : chaque tâche a son propre horaire, son activation, son package cible et sa séquence d'actions.
- Enregistrement lié à une application : l'enregistrement démarre dès que vous basculez vers l'application cible, se met en pause quand vous quittez et reprend à votre retour ; il se met aussi en pause sur écran verrouillé ou éteint.
- Enregistrement « nu » : avec un nom de package vide, il enregistre depuis l'écran allumé, en filtrant les balayages de bord et du bas selon des règles.
- À la relecture, le module gère le réveil de l'écran, le déverrouillage, le lancement de l'application cible et la confirmation du premier plan, puis restaure le verrouillage d'orientation, le maintien d'éveil et le délai d'extinction.
- **Nettoyage de l'arrière-plan après chaque exécution** : l'application cible est fermée avec `am force-stop` à la fin de la tâche, afin qu'elle ne retienne plus de mémoire et que la tâche suivante démarre dans un état propre. Un interrupteur global, plus une surcharge par tâche.
- **WebUI multilingue** : chinois / English / Français / Русский, sélectionnable en haut à droite ; le choix est mémorisé.
- **Prise en charge de plusieurs appareils** : une couche de profil d'appareil permet d'ajuster par modèle la taille de l'écran, l'ID d'affichage et la disposition du pavé numérique de l'écran de verrouillage, afin que l'enregistrement, la relecture et le déverrouillage PIN fonctionnent aussi sur d'autres téléphones HyperOS 4. La base mesurée du Xiaomi 17 Pro est conservée telle quelle et n'est pas affectée.
- **Le WebUI se met à jour avec le module** : les ressources portent une version, la mise en cache est désactivée, et la page vérifie d'elle-même si le document est périmé puis le recharge — plus besoin de désinstaller puis réinstaller après une mise à jour.
- **Une interface plus aérée** : un résumé d'état en haut, tout le détail rangé dans des sections repliables, pour que le premier écran ne soit plus un mur de formulaire ; tout déplier / tout replier en un geste.
- Le code PIN n'est écrit que dans la configuration locale et n'apparaît jamais dans l'état, le journal ni le code source.

## Environnement requis

Le module n'utilise que les points d'entrée standard `customize.sh` + `service.sh` : **ni Zygisk, ni modification de `/system`, ni metamodule requis**. La planification, l'enregistrement/relecture et le déverrouillage PIN fonctionnent donc aussi sous Magisk / APatch.

Le WebUI n'est **pas plus réservé à KernelSU**. APatch propose le WebUI de module depuis la version 10568, et il fait exactement ce que fait KernelSU : il sert `webroot/` depuis `https://mui.kernelsu.org` et injecte un objet global **du même nom**, `ksu` — celui auquel parle le `kernelsu.js` de ce module. Le WebUI fonctionne donc sous APatch sans la moindre modification. Il en va de même pour les forks de KernelSU (KernelSU Next, SukiSU Ultra).

Magisk est la seule exception : le code amont de Magisk ne contient **aucun code WebView** — pas « non implémenté », simplement aucune capacité de ce type — et il n'affichera donc pas `webroot/` tout seul. Pour y utiliser le WebUI, il faut une application hôte qui en fournisse un :

| Fonctionnalité | KernelSU / forks | APatch | Magisk |
| --- | :---: | :---: | :---: |
| Planification / enregistrement / relecture / déverrouillage PIN | ✅ | ✅ | ✅ |
| WebUI du module | ✅ | ✅ | ✅ avec KsuWebUI ou MMRL |

**KsuWebUI** et **MMRL** obtiennent chacun le root sur Magisk eux-mêmes, puis injectent ce même objet global `ksu` dans `webroot/`. Une fois l'un d'eux installé, ce module ne demande aucune modification et le WebUI fonctionne tel quel — c'est la pratique adoptée dans tout l'écosystème sur Magisk. Ce module fournit un `config.json` déclarant `"webui-engine": "ksu"`, afin que MMRL choisisse son moteur compatible `ksu` plutôt que son WebUI X par défaut (dont l'API n'est pas compatible).

> ⚠️ Les deux voies fonctionnent, mais **KsuWebUI est la plus solide** : c'est une application autonome qui obtient elle-même le root et ne dépend d'aucun gestionnaire. Le moteur compatible `ksu` de MMRL est marqué obsolète dans sa dépendance WebUI X Portable depuis le 2026-03-14 — MMRL épingle actuellement une version de 7 heures antérieure, ce qui fonctionne pour l'instant, et cela pourrait cesser après une mise à jour de MMRL. Si cela arrive, passez à KsuWebUI ; ce module n'a rien à changer.

Dans tous les environnements, vous pouvez piloter le même backend depuis un shell root via `webctl.sh` :

```shsu -c 'sh /data/adb/modules/icbc_daily_water/webctl.sh status'
su -c 'sh /data/adb/modules/icbc_daily_water/webctl.sh settime 0730'
su -c 'sh /data/adb/modules/icbc_daily_water/webctl.sh trigger'      # lance immédiatement la tâche intégrée
su -c 'WEBUI_PIN=123456 sh /data/adb/modules/icbc_daily_water/webctl.sh setpin'
```

Le code PIN n'est Deliberément accepté **que via la variable d'environnement `WEBUI_PIN`**, jamais en argument de ligne de commande, afin que le texte en clair n'apparaisse jamais dans la liste des processus. Tapez cette dernière ligne à la main dans un terminal local — ne la mettez ni dans un script, ni dans un alias, ni dans une discussion.

La liste complète des sous-commandes figure en en-tête du fichier : `webctl.sh status|setpin|settime|setenable|setmode|setopen|setsleep|setwatch|setcleanup|trigger[NAME]|restart|log|profiles|profile add/del/set|record start/stop/status`.

## Installation

1. Téléchargez `XiaomiAutomation-v0.12.7.zip` depuis les Releases.
2. Flashez ce zip dans KernelSU / Magisk.
3. Redémarrez, ouvrez le WebUI du module et réglez la méthode de déverrouillage et le code PIN selon vos besoins.
4. Pour une tâche enregistrée, renseignez le nom de package de l'application cible ; basculez vers cette application et appuyez sur « Démarrer l'enregistrement », puis sur « Arrêter l'enregistrement » lorsque vous avez terminé.

### Mise à jour depuis une version antérieure

Il suffit de flasher le nouveau zip par-dessus l'ancien. Pour conserver votre configuration et vos tâches, les identifiants de compatibilité internes sont inchangés :

```text
id=icbc_daily_water
/data/adb/modules/icbc_daily_water
/data/adb/icbc_water
```

Ne supprimez pas ces répertoires et ne modifiez pas l'identifiant du module ; votre configuration, vos profils, votre code PIN et vos actions enregistrées sont conservés.

> Si le WebUI semble encore obsolète après la mise à jour, vérifiez la version en haut à droite : elle doit indiquer `v0.12.4`. Sinon, l'ancien paquet a été installé.

## Utilisation

### Tâche intégrée

La tâche « Arrosage ICBC quotidien » est créée à la première installation. C'est un profil script qui appelle le `water.sh` intégré, lequel effectue la vérification de la page d'accueil d'ICBC, appuie sur l'entrée de la tâche et déroule le processus d'arrosage. L'horaire par défaut est `07:30` et peut être modifié dans le WebUI.

### Tâches enregistrées

1. Ajoutez une tâche dans le WebUI avec un nom et un package cible ; laisser le package vide enregistre tout l'écran allumé.
2. Appuyez sur « Démarrer l'enregistrement » sur la tâche, puis basculez vers l'application cible.
3. Revenez au WebUI et appuyez sur « Arrêter l'enregistrement ».
4. Vérifiez le nombre d'actions, puis lancez-la immédiatement ou attendez son horaire.

Pour capturer les gestes de retour par le bord, renseignez le package cible : le mode lié à l'application conserve les balayages de bord et ignore les effectués dans d'autres applications.

### Nettoyage de l'arrière-plan

« ⚙️ Autres → Nettoyer l'application en arrière-plan ensuite » contrôle la fermeture automatique de l'application cible après chaque tâche. Elle est **activée par défaut**. Seuls les processus sont libérés ; les données, les comptes et l'état de connexion ne sont jamais effacés.

Deux cas particuliers à connaître :

- **Tâches enchaînées dans la même application** : si vous découpez le parcours d'une application en plusieurs tâches (par exemple une première moitié et une seconde moitié), fermer l'application après la première renvoie la suivante à l'écran d'accueil. Réglez les tâches *au milieu* de la chaîne sur « Désactivé (garder en arrière-plan) » et ne gardez le nettoyage que sur la dernière tâche de la chaîne.
- **Tâches « nues »** (sans nom de package) : il n'y a pas d'application cible bien définie, le service ne peut donc pas savoir quel processus fermer. Elles ne sont pas nettoyées automatiquement ; la carte de la tâche l'indique.

« Arroser à la première ouverture quotidienne d'ICBC » suit un autre chemin : vous tenez le téléphone et avez ouvert ICBC vous-même, le module ne vous fermera donc pas l'application.

### Écran de verrouillage et alimentation

Avant une tâche, le module tente de réveiller et de déverrouiller l'écran, soit par saisie aveugle du code PIN, soit par balayage vers le haut. Il maintient l'écran allumé pendant l'exécution puis restaure le verrouillage d'orientation, `screen_off_timeout` et le maintien d'éveil d'origine. Si l'état de verrouillage ne peut pas être confirmé, il abandonne en toute sécurité au lieu d'injecter des coordonnées à l'aveugle.

### Langue

Le menu déroulant en haut à droite permet de basculer entre chinois / English / Français / Русский ; le choix est enregistré dans le stockage local du navigateur. Les lignes de journal, les commandes et les noms de package sont du contenu technique et restent non traduits.

## Appareils et calibrage

L'appareil cible par défaut est le Xiaomi 17 Pro. Le module détecte l'appareil tactile via `getevent -p` et convertit les coordonnées à partir de la plage des axes tactiles.

### Changer de téléphone : le profil d'appareil

La carte « 📱 Profil d'appareil » agit sur exactement trois choses : **la largeur et la hauteur de l'écran, l'ID d'affichage et la disposition du pavé numérique de l'écran de verrouillage**. Ce sont ces valeurs qui déterminent si l'enregistrement, la relecture et le déverrouillage PIN fonctionnent ; elles diffèrent sur les autres téléphones et demandent donc leurs propres valeurs.

- **Xiaomi 17 Pro** : la carte contient déjà les valeurs mesurées — **n'y touchez pas**. Laissez « Activer le remplacement » désactivé et le module utilise les valeurs d'origine de `water.sh` / `sched.conf`.
- **Autres modèles HyperOS 4** (Xiaomi 17, 17 Pro Max, …) : appuyez sur « 🔍 Détecter ce téléphone » pour remplir `wm size` et `wm density`, vérifiez les valeurs, puis cochez « Activer le remplacement » et enregistrez. Le pavé numérique de l'écran de verrouillage ne peut pas être détecté de façon fiable : remplissez-le à la main — sinon les valeurs du 17 Pro sont utilisées et les mauvais chiffres sont tapés.
- Le profil se trouve dans `/data/adb/icbc_water/device.conf`. `DEV_APPLY=0` (par défaut) signifie « pas de remplacement, on utilise la base du 17 Pro » ; seul `DEV_APPLY=1` active le remplacement. Chaque valeur doit passer un contrôle « unique + chiffres uniquement » : une erreur ou un fichier corrompu laisse au pire le remplacement inactif — il ne peut pas casser le processus d'arrosage.

> **Tous les modèles autres que le Xiaomi 17 Pro sont « en test ».** La résolution, le DPI et la hauteur des barres système influencent la mise en page de l'interface, par conséquent : **le parcours ICBC n'est pas garanti** ; mais **l'enregistrement, la relecture et le déverrouillage PIN fonctionnent normalement**. Ne l'essayez pas sur votre téléphone principal.

### Relire des actions enregistrées sur un autre téléphone

Chaque tâche enregistrée dispose d'une liste « Sans mise à l'échelle / Mettre à l'échelle ». Si une tâche a été enregistrée sur un téléphone à la **résolution différente** et que vous souhaitez la relire ici, choisissez « Mettre à l'échelle » : le module lit la résolution inscrite dans l'en-tête du fichier et convertit chaque coordonnée proportionnellement. Le réglage par défaut est « Sans mise à l'échelle » : un enregistrement puis une relecture sur le même téléphone ne sont donc pas affectés.

### Coordonnées du parcours ICBC

Les sondes de pixels et les coordonnées du parcours ICBC sont regroupées dans le bloc de configuration en haut de `water.sh`. Un script utilitaire est fourni pour inspecter la couleur des pixels d'une capture :

```sh
python3 tools/px.py screen.png 216,778 518,780 746,748
```

## Fichiers

| Fichier | Rôle |
|---|---|
| `module.prop` | Métadonnées du module (nom affiché, version, auteur) |
| `service.sh` | Daemon et planificateur multi-profils, réveil/déverrouillage/restauration d'alimentation, nettoyage après exécution |
| `water.sh` | Logique métier de l'arrosage ICBC intégré |
| `record.sh` | Noyau d'enregistrement des événements tactiles |
| `replay.sh` | Noyau de relecture des actions enregistrées |
| `webctl.sh` | Interface de commandes root pour le WebUI |
| `webroot/` | Page WebUI KernelSU, scripts et dictionnaires de traduction |
| `sched.conf` | Modèle de configuration par défaut (la configuration active est dans `/data/adb/icbc_water/`) |
| `device.conf` | Modèle de profil d'appareil (le fichier actif est dans `/data/adb/icbc_water/device.conf`) |
| `customize.sh` | Flux d'installation/mise à jour, permissions et contrôle d'intégrité du WebUI |
| `tools/px.py` | Outil de calibrage par pixel d'une capture |
| `tools/run_once.sh` | Exécution manuelle du parcours ICBC intégré |
| `tools/build_zip.sh` | Production du zip installable depuis le dépôt |

## Compilation depuis les sources

Exécutez ceci à la racine du dépôt :

```sh
bash tools/build_zip.sh
```

Le script écrit le fichier suivant dans le répertoire parent :

```text
XiaomiAutomation-v0.12.7.zip
```

## Licence

[MIT](LICENSE) License.
