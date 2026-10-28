# Installer Blip

## Prérequis

- macOS 14 (Sonoma) ou plus récent, sur Apple Silicon ou Intel
- Un compte GitHub, avec au choix :
  - [GitHub CLI](https://cli.github.com) (`brew install gh`) connecté via `gh auth login` : c'est le plus simple ;
  - ou un token *classic* avec les scopes `notifications` et `repo`.

## 1. Installer l'app

### Depuis la dernière release (recommandé)

```sh
curl -fsSL https://github.com/nihiloproxima/blip/releases/latest/download/Blip.zip -o /tmp/Blip.zip \
  && ditto -x -k /tmp/Blip.zip /Applications && open /Applications/Blip.app
```

Passer par le terminal évite le blocage de Gatekeeper. Blip est signé ad hoc mais pas notarié par Apple, et macOS refuse d'ouvrir une app non notariée téléchargée depuis un navigateur. Si tu as quand même téléchargé `Blip.zip` depuis la [page des releases](https://github.com/nihiloproxima/blip/releases), dézippe-le dans `/Applications`, puis :

```sh
xattr -dr com.apple.quarantine /Applications/Blip.app
```

ou, après une première tentative d'ouverture, va dans Réglages Système › Confidentialité et sécurité › « Ouvrir quand même ».

### Depuis les sources

Il faut Xcode 16 ou plus récent, pour Swift 6. Lance-le une première fois pour accepter la licence, ou passe par `sudo xcodebuild -license accept`.

```sh
git clone https://github.com/nihiloproxima/blip.git
cd blip
./scripts/build.sh --install
```

Le script compile une app universelle en release, assemble `build/Blip.app` (icône comprise, signature ad hoc), la copie dans `/Applications` puis la lance. Sans `--install`, il s'arrête à `build/Blip.app`, que tu peux déplacer où tu veux.

## 2. Trouver le compagnon

Blip n'a pas d'icône dans le Dock : il apparaît uniquement dans la barre de menus, sous la forme d'un petit blob.

> Sur un MacBook à encoche, une barre de menus trop chargée masque les icônes en trop. Si le blob n'apparaît pas, libère de la place (⌘ + glisser pour retirer d'autres icônes) ou utilise un utilitaire comme Ice ou Bartender.

## 3. Se connecter à GitHub

Clique sur le blob. Deux options :

**Avec GitHub CLI (recommandé).** Clique sur « Utiliser mon compte GitHub CLI ». Blip relit `gh auth token` à chaque lancement et ne stocke aucun secret. `gh` doit être installé dans `/opt/homebrew/bin`, `/usr/local/bin` ou `/usr/bin`.

**Avec un token.** Crée un [token classic](https://github.com/settings/tokens/new?scopes=notifications,repo&description=Blip) avec les scopes `notifications` et `repo`, colle-le puis valide. Il est rangé dans le trousseau macOS (service `io.github.nihiloproxima.blip`).

> Les tokens *fine-grained* ne fonctionnent pas : l'API notifications de GitHub ne les accepte pas.

## 4. Réglages conseillés

L'engrenage du popover donne accès à :

- **Lancer à l'ouverture de session**, pour que Blip démarre avec le Mac ;
- **Bannières macOS** : macOS demande l'autorisation au premier lancement, et un clic sur une bannière ouvre le fil sur GitHub ;
- **Seulement celles qui me concernent**, pour ignorer les dépôts que tu surveilles sans y participer ;
- **Archiver plutôt que marquer lu**, pour que les fils triés disparaissent aussi de la boîte de réception web ;
- le nom du compagnon et les sons.

## Mettre à jour

Blip vérifie lui-même les nouvelles releases, au lancement puis toutes les 6 heures. Quand une version sort, un bandeau apparaît en bas du popover : « Installer et relancer » télécharge la release, vérifie le bundle et sa signature, remplace l'app et la relance. Les réglages affichent la version installée et permettent de lancer la vérification à la main.

Si tu compiles depuis les sources :

```sh
git pull
./scripts/build.sh --install
```

Dans les deux cas, ta progression (XP, niveau, série) et ta connexion sont conservées.

## Désinstaller

Si tu avais activé le lancement automatique, décoche d'abord « Lancer à l'ouverture de session » dans les réglages de Blip. Ensuite :

```sh
pkill -x Blip
rm -rf /Applications/Blip.app
defaults delete io.github.nihiloproxima.blip                        # réglages et progression
security delete-generic-password -s io.github.nihiloproxima.blip    # token, si tu en avais collé un
```

## Développement

```sh
swift run Blip              # lance Blip hors bundle (sans bannières macOS ni mises à jour, qui exigent un .app)
swift run Blip -demo 9      # mode démo : 9 fausses notifications, sans réseau ni token
```

Le mode démo sert aux captures d'écran. `-demo 0` affiche l'écran d'inbox zero, et la progression se règle avec les mêmes options : `-xp 620 -streak 4 -bestCombo 5`.

## Dépannage

| Problème | Solution |
| --- | --- |
| « GitHub CLI n'a pas renvoyé de token » | Lance `gh auth login`, puis `gh auth status` pour vérifier. |
| « GitHub a refusé le token » | Token expiré, révoqué ou fine-grained : crée un token classic avec `notifications` et `repo`. |
| Les notifications d'une organisation manquent | Avec un token, autorise-le pour l'organisation (SSO) depuis la page des tokens GitHub. |
| Aucune bannière | Réglages Système › Notifications › Blip, puis autorise les alertes. |
| « Blip est endommagé » ou « ne peut pas être ouvert » | L'app a été téléchargée par un navigateur : `xattr -dr com.apple.quarantine /Applications/Blip.app`, ou installe-la avec la commande `curl` ci-dessus. |
| Le bandeau de mise à jour propose seulement « Télécharger » | Blip n'est pas dans un dossier modifiable (image disque, translocation Gatekeeper) : déplace-le dans `/Applications`. |
| `error: package requires minimum Swift tools version 6.0` | Mets Xcode à jour, puis `sudo xcode-select -s /Applications/Xcode.app`. |
