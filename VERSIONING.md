# Versionierung und Build-Tags

Das Projekt verwendet Semantic Versioning (`MAJOR.MINOR.PATCH`) mit einem
vorangestellten `v` bei Git-Tags.

## GitFlow

- `main` enthaelt ausschliesslich getestete Release-Staende.
- `develop` ist der Integrationszweig fuer die naechste Version.
- Aenderungen werden in kurzlebigen `feature/<name>`-Branches entwickelt und
  nach gezielten Tests in `develop` integriert.
- Release-Tags werden annotiert auf den getesteten Release-Commit gesetzt.

- `MAJOR`: inkompatible Aenderungen an Datenformat, Update- oder
  Konfigurationsschnittstellen.
- `MINOR`: neue, abwaertskompatible Funktionen.
- `PATCH`: abwaertskompatible Fehlerkorrekturen.
- Entwicklungsstaende tragen einen SemVer-Praelease-Suffix, beispielsweise
  `0.1.0-dev.1`.

`VERSION` ist die Quellversion. Ein Image-Build wird einem Commit und einem
SemVer-Tag zugeordnet. Release-Tags werden erst gesetzt, wenn der Build
erfolgreich war und das Image auf dem Zielgeraet getestet wurde. Der erste
funktionsfaehige Prototyp ist fuer `v0.1.0` vorgesehen. Build-Artefakte und
PICO-8-Installationsarchive werden nicht in Git eingecheckt.

Fuer einen verifizierten Build:

1. `VERSION` auf die Release-Version setzen.
2. Aenderungen committen.
3. Den Build erstellen und auf dem Zielgeraet testen.
4. Den getesteten Commit annotiert taggen, zum Beispiel:

   ```sh
   git tag -a v0.1.0 -m "PicoOS prototype 0.1.0"
   ```

5. Das Image mit Tag und Commit-ID archivieren.
