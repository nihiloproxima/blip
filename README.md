# Blip

Tes notifications GitHub dans la barre de menus macOS, avec un compagnon en pixel art qui grandit quand tu les tries. App native, sans dépendance, environ 2 Mo.

<p align="center">
  <img src="docs/screenshots/notifications.png" width="420" alt="Popover de Blip avec neuf notifications groupées par dépôt">
</p>

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/mes-pr.png" width="260" alt="Onglet Mes PR"><br>Mes PR</td>
    <td align="center"><img src="docs/screenshots/inbox-zero.png" width="260" alt="Inbox zero"><br>Inbox zero</td>
    <td align="center"><img src="docs/screenshots/connexion.png" width="260" alt="Connexion"><br>Connexion</td>
  </tr>
</table>

## Installation

macOS 14 ou plus récent :

```sh
curl -fsSL https://github.com/nihiloproxima/blip/releases/latest/download/Blip.zip -o /tmp/Blip.zip \
  && ditto -x -k /tmp/Blip.zip /Applications && open /Applications/Blip.app
```

Depuis les sources (Xcode 16+) : `./scripts/build.sh --install`.

Connecte-toi ensuite avec GitHub CLI (`gh auth login`) ou avec un token classic (scopes `notifications` et `repo`). Pour le reste, voir le [guide d'installation](INSTALL.md).

Blip se met à jour tout seul : quand une release sort, il propose de l'installer.

## Utilisation

Il y a cinq onglets : Notifs, Mes PR, Reviews, Assignées et Historique.

| Touche | Action |
| --- | --- |
| ⌘1 à ⌘5 | changer d'onglet |
| ⌘F | rechercher |
| ↑ ↓ | sélectionner |
| ↩ | ouvrir (et marquer lu) |
| ⌘↩ | ouvrir en arrière-plan |
| E ou ⌫ | marquer lu |
| M | se désabonner |

## Le jeu

Chaque notification triée rapporte de l'XP : de 5 à 30 selon son importance, multipliée jusqu'à x5 si tu enchaînes en moins de 8 s. Les niveaux débloquent une pousse (5), une casquette (10) et une couronne (20). Chaque inbox zero quotidien prolonge ta série, et les week-ends ne la cassent pas.

L'humeur du compagnon suit le nombre de non lues : zen à 0, content jusqu'à 4, inquiet jusqu'à 14, puis panique.

## Publier une version

```sh
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.2.0" Resources/Info.plist
git commit -m "Version 0.2.0" Resources/Info.plist && git tag v0.2.0 && git push && git push --tags
```

La CI compile et publie `Blip.zip` dans la release.
