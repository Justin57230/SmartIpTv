# Guide d'installation — v1.0.0

L'application est disponible sur Android, iOS, Web et Windows.

---

## Android — Installation APK

1. Téléchargez le fichier `.apk` dans la section **Assets** de cette Release.
2. Ouvrez le fichier téléchargé.
3. Autorisez l'installation depuis cette source si Android le demande.
4. Appuyez sur **Installer**.
5. Une fois terminé, ouvrez l'application.

---

## iOS — Installation IPA avec SideStore

SideStore permet d'installer des applications iOS sans passer par l'App Store et sans jailbreak.

### Prérequis

- Un iPhone ou iPad.
- Un ordinateur Windows, macOS ou Linux pour la première installation.
- Un compte Apple.
- Une connexion Wi-Fi.
- Le fichier `.ipa` de l'application.

### Étape 1 — Installer SideStore

1. Consultez la [documentation officielle de SideStore](https://docs.sidestore.io/docs/installation/prerequisites).
2. Installez LocalDevVPN depuis l'App Store.
3. Sur votre ordinateur, téléchargez et ouvrez iloader.
4. Connectez votre iPhone à votre ordinateur avec un câble USB.
5. Faites confiance à l'ordinateur sur votre iPhone si nécessaire.
6. Connectez-vous avec votre compte Apple dans iloader.
7. Sélectionnez votre appareil.
8. Cliquez sur **Install SideStore (Stable)**.

### Étape 2 — Configurer SideStore

1. Sur votre iPhone, ouvrez Réglages.
2. Allez dans Général → VPN et gestion de l'appareil.
3. Faites confiance au profil développeur correspondant à votre compte Apple.
4. Si demandé, activez le mode développeur dans Confidentialité et sécurité.
5. Ouvrez LocalDevVPN et appuyez sur Connect.
6. Lancez SideStore.
7. Connectez-vous avec le même compte Apple que celui utilisé dans iloader.
8. Allez dans **My Apps**.
9. Appuyez sur le compteur de 7 jours à côté de SideStore pour effectuer le premier rafraîchissement.

### Étape 3 — Installer notre application

1. Téléchargez le fichier `.ipa` depuis les Assets de cette Release.
2. Transférez-le sur votre iPhone (AirDrop, iCloud Drive ou téléchargement direct).
3. Ouvrez SideStore.
4. Rendez-vous dans l'onglet **My Apps**.
5. Appuyez sur le bouton `+`.
6. Sélectionnez le fichier `.ipa` téléchargé.
7. Patientez pendant la signature et l'installation.
8. L'application apparaît sur votre écran d'accueil.

### Renouvellement de signature

Avec un compte Apple gratuit, les applications installées de cette manière ont généralement une validité de 7 jours.

Pensez à rafraîchir régulièrement vos applications depuis SideStore. LocalDevVPN doit être connecté pour effectuer cette opération.

---

## Web — Installation navigateur

1. Téléchargez l'archive Web si elle est fournie.
2. Extrayez son contenu.
3. Hébergez le dossier `build/web` sur un serveur Web compatible.
4. Ouvrez l'adresse Web de l'application dans votre navigateur.
5. Vous pouvez ajouter l'application à votre écran d'accueil si votre navigateur le permet.

Aucune installation classique n'est nécessaire.

---

## Windows — Installation PC

1. Téléchargez l'archive Windows `.zip` depuis les Assets.
2. Faites un clic droit sur l'archive.
3. Sélectionnez **Extraire tout**.
4. Ouvrez le dossier extrait.
5. Lancez le fichier `.exe`.
6. L'application démarre.

**Important :** conservez le fichier `.exe`, les DLL et le dossier `data` ensemble. Ne déplacez pas uniquement l'exécutable.

---

## Assistance et signalement

Si vous rencontrez un problème lors de l'installation ou de l'utilisation :

- Vérifiez que vous avez téléchargé la bonne version.
- Vérifiez la compatibilité de votre appareil.
- Signalez les erreurs dans la section Issues du dépôt GitHub.

---

**Merci d'utiliser l'application ! ❤️**

*Version initiale — v1.0.0*
