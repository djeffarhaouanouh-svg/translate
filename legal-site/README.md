# Swayco — Site légal

Site statique avec les pages obligatoires pour la publication sur App
Store / Play Store : Conditions d'utilisation, Politique de
confidentialité, FAQ.

## Pages

| URL cible | Fichier |
|---|---|
| `https://swayco.fr/` | `index.html` |
| `https://swayco.fr/terms` | `terms.html` |
| `https://swayco.fr/privacy` | `privacy.html` |
| `https://swayco.fr/help` | `help.html` |

L'app Flutter lie ces URLs depuis l'écran Paramètres
(`lib/screens/settings_screen.dart`). N'importe quel changement de
chemin doit être répercuté côté Flutter.

## Déploiement

### Option 1 — Vercel (recommandé, gratuit)

```bash
cd legal-site
npx vercel --prod
```

Vercel sert automatiquement `terms.html` pour `/terms` (clean URLs
activé par défaut). Liaison du domaine `swayco.fr` se fait depuis
le dashboard Vercel.

### Option 2 — Netlify

```bash
cd legal-site
netlify deploy --prod
```

Sur Netlify, ajouter à la racine un fichier `_redirects` :

```
/terms /terms.html 200
/privacy /privacy.html 200
/help /help.html 200
```

### Option 3 — Tout serveur statique (Apache, Nginx)

Activer la réécriture pour servir `.html` quand l'extension est
omise. Exemple Apache `.htaccess` à la racine :

```apache
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME}.html -f
RewriteRule ^(.*)$ $1.html [L]
```

## Personnalisation

Avant submission, vérifier / adapter :

* **Couleurs et logo** (`style.css`, lignes `--primary` etc.) si
  ton branding final est différent.
* **Date de mise à jour** (haut de chaque page) à la date réelle de
  publication.
* **Email support** (`support@swayco.fr` partout) si l'adresse
  finale est différente.
* **Mentions légales** propres à ta structure juridique (nom de
  société, SIRET, capital social, hébergeur — obligatoire en
  France pour un site commercial). À ajouter en bas de
  `terms.html` ou dans une page séparée `legal.html`.

## Notes pour l'examen App Store / Play Store

* **Apple §5.1.1** : Privacy Policy URL doit être accessible
  publiquement (pas derrière un login) — OK avec ce site.
* **Apple §5.1.1(v)** : la procédure de suppression de compte doit
  être détaillée dans la Privacy Policy ET réellement implémentée
  dans l'app — OK (`privacy.html` section 6 + `help.html` section
  "Mon compte").
* **Play Data Safety form** : les types de données déclarés doivent
  matcher `privacy.html` section 2. Remplir le formulaire dans
  Play Console au moment de la soumission.
