# Pico-8-Konsole: Projektplan

## Ziel

Ein schlankes, mit Buildroot erstelltes Linux-System fuer eine selbstgebaute
PICO-8-Konsole. Primaeres Zielgeraet ist der Raspberry Pi Zero 2 W; zusaetzlich
soll der Raspberry Pi Zero W unterstuetzt werden. Dafuer sind getrennte
Build-Profile bzw. Images vorgesehen. Das Image soll keine PICO-8-Binaries oder
Cartridges enthalten.

Das Projekt wird mit Git und Semantic Versioning verwaltet. Der erste
verifizierte Prototyp ist fuer `v0.1.0` vorgesehen; Tags werden erst fuer
erfolgreich gebaute und auf dem Zielgeraet getestete Images gesetzt.

## Bisher festgelegte Anforderungen

- Zielgeraete: Raspberry Pi Zero 2 W (primaer) und Raspberry Pi Zero W
  (zusaetzliches, moeglicherweise eingeschraenktes Profil).
- Getrennte Images/Build-Profile fuer die unterschiedlichen Prozessoren und
  deren Anforderungen.
- Die erste Buildroot-Konfiguration verwendet 32-Bit-ARM fuer breite
  Kompatibilitaet. Damit das System auch auf dem Zero W lauffaehig sein kann,
  muss die Userspace-Toolchain mindestens ARMv6-kompatibel sein; die
  Zero-2-W-Leistung wird anschliessend gemessen.
- Die Kernel-Konfiguration wird aus dem Raspberry-Pi-Boardprofil abgeleitet
  und mit einem versionierten, hardwarebezogenen Fragment um nicht benoetigte
  Treiber und Dateisysteme bereinigt. Erhalten bleiben die benoetigten Pfade
  fuer Broadcom-WLAN/Bluetooth, VC4/HDMI, Audio, SD/ext4/FAT32, USB-Speicher und
  Controller-Eingaben.
- Standard-Zielmedium fuer das erste SD-Karten-Image ist eine 16-GB-Karte;
  die Datenpartition wird beim ersten Systemstart bis zum Ende der SD-Karte
  vergroessert, sodass groessere Karten den zusaetzlichen Platz ebenfalls
  nutzen.
- Erster vollstaendiger Image-Meilenstein fuer den Zero 2 W: bootfaehiges
  Buildroot-Image mit Bootsplash, HDMI-Terminal, Setup-AP/Konfigurationsportal,
  SSH, A/B-Systemslots und SWUpdate. Updates muessen per Web-Upload und per
  Abruf von einem Update-Server moeglich sein.
- Die Verwaltungsoberflaeche fuer die HUB75-Matrix soll nativ auf einer
  128x128-Pixel-Canvas laufen und sich beim Layout am PICO-8-Terminal
  orientieren, einschliesslich des charakteristischen pixelbasierten
  Monospace-Schriftbilds. Sie ist eine kompakte, speziell fuer die Matrix
  entwickelte Bedienoberflaeche und kein vollstaendiges Linux-Textterminal.
  Eine normale Shell bleibt fuer Diagnose ueber HDMI und SSH verfuegbar. Die
  Schrift muss aus einer rechtmaessig nutzbaren Quelle stammen; ein
  proprietaeres Font-Asset wird nicht ungeprueft extrahiert oder in das Image
  uebernommen.
- Als Architekturvorschlag soll dieselbe Verwaltungslogik sowohl die lokale
  128x128-Oberflaeche als auch eine Browser-Remote-View/Fernsteuerung bedienen.
  Der Browser kann die Pixeloberflaeche gespiegelt anzeigen und Eingaben
  zuruecksenden. Protobuf eignet sich fuer typisierte Status- und
  Steuerbefehle; Bildframes sollten als effiziente Binaerdaten ueber einen
  WebSocket-Transport uebertragen werden, nicht als Protobuf-Text. Das
  responsive WLAN-Ersteinrichtungsportal bleibt als separate Weboberflaeche
  vorgesehen, da das winzige Konsolenlayout auf dem Handy unpraktisch ist.
- SSH ist standardmaessig aktiv und nur aus dem LAN erreichbar.
- Hostname: `pico8`; WLAN bezieht seine Adresse per DHCP. Avahi kuendigt
  den Host per mDNS/DNS-SD als `pico8.local` im lokalen WLAN an.
- WLAN-Zugangsdaten liegen persistent in `/data/network/wpa_supplicant.conf`.
  Die FAT32-Datenpartition wird unter Linux mit root-exklusiven Mount-Masken
  eingebunden; der WLAN-Dienst verwendet eine root-eigene RAM-Kopie mit Modus
  0600 unter `/run/picoos-wifi/`. Private Zugangsdaten bleiben ausserhalb von Git
  und oeffentlichen Images. Fuer den Bring-up ist lokale Provisionierung
  vorgesehen, bis das Setup-Portal implementiert ist.
- SSH verwendet den unprivilegierten Systembenutzer `pico`; direkter
  SSH-Root-Login ist deaktiviert. Der Basis-Ed25519-Schluessel liegt als
  `/data/ssh/base-key.pub` auf der Datenpartition. Beim Systemstart wird
  `pico`'s `authorized_keys` mit diesem Schluessel abgeglichen. Ersetzt der
  Nutzer die Schluesseldatei auf der Datenpartition, wird sein eigener
  Schluessel verwendet.
- Im oeffentlichen Image werden keine privaten WLAN-Zugangsdaten eingetragen.
  Fuer den Bring-up koennen sie lokal auf die Datenpartition provisioniert
  werden; spaeter uebernimmt das Setup-WLAN mit Konfigurationsportal diese
  Aufgabe. Nach erfolgreicher WLAN-Einrichtung ist SSH im LAN erreichbar.
- Das Setup-WLAN erhaelt pro Geraet ein eigenes zufaelliges Passwort. SSID,
  Passwort und Portal-Adresse sollen in einem QR-Code bereitgestellt werden.
- Der vom Nutzer bereitgestellte oeffentliche SSH-Schluessel wird als
  `/data/ssh/base-key.pub` auf der Datenpartition bereitgestellt und beim
  Systemstart fuer den Benutzer `pico` aktiviert. Die Datei auf der
  Datenpartition ist die Quelle der Wahrheit; ein dort vom Nutzer abgelegter
  eigener Schluessel ersetzt den Basis-Schluessel. Der private Schluessel
  verbleibt ausschliesslich beim Nutzer.
- Das Passwort `PICO8` ist fuer Anmeldungen aus dem LAN vorgesehen. Es ist ein
  bekanntes, leicht zu erratendes Standardpasswort und daher ein bewusstes
  Sicherheitsrisiko; vor einem Einsatz in nicht vertrauenswuerdigen Netzen
  sollte es geaendert oder die Passwortanmeldung deaktiviert werden.
- Systemupdates sollen A/B-Slots verwenden, damit ein fehlgeschlagenes Update
  einen Rueckfall auf das vorherige System ermoeglicht.
- U-Boot soll die A/B-Slots auswaehlen und mit Boot-Zaehler sowie
  Bestaetigung des erfolgreichen Systemstarts einen automatischen Rueckfall
  auf den vorherigen Slot ermoeglichen.
- SWUpdate soll Updates sowohl ueber ein Webinterface (Paket-Upload) als auch
  durch Abruf von einem Update-Server einspielen koennen.
- PICO-8-Dateien und spaetere Nutzerdaten liegen auf einer separaten
  FAT32-Datenpartition, damit Windows, macOS und Linux darauf zugreifen koennen.
  FAT32 speichert keine Unix-Rechte oder Symlinks; einzelne Dateien duerfen
  hoechstens 4 GiB minus ein Byte gross sein. Die automatische Erweiterung auf
  den verfuegbaren Rest der SD-Karte ist weiterhin geplant, nicht implementiert.
- Das Image soll die benoetigten Laufzeitvoraussetzungen fuer PICO-8
  bereitstellen, obwohl PICO-8-Binary und Cartridges nicht mitgeliefert
  werden. Die konkreten Bibliotheken und Audio-/Grafik-Schnittstellen muessen
  anhand der eingesetzten PICO-8-Version festgelegt werden. Insbesondere die
  Kompatibilitaet des vom Nutzer bereitgestellten PICO-8-Binaries und die
  Leistung auf dem aelteren Zero W muessen praktisch geprueft werden.
- Als lokale Installationsquelle liegt `pico8/pico-8_0.2.7_raspi.zip` vor.
  Das Archiv enthaelt 32-Bit-ARM-Varianten (`pico8`, `pico8_dyn`,
  `pico8_gpio`) und eine 64-Bit-AArch64-Variante (`pico8_64`). Das zum
  Zielsystem passende Binary soll bei der Provisionierung auf die
  Datenpartition installiert werden; PICO-8 bleibt ausserhalb des
  Buildroot-Systemimages.
- Bluetooth soll Audioausgabe sowie das Koppeln und Verwenden von Gamepads,
  Joysticks und vergleichbaren Eingabegeraeten unterstuetzen.
- Fuer analoge Ausgabe sind Composite-Video (Cinch/RCA) und Audio vorgesehen.
  Die Signale koennen bei Bedarf an den Loetpads/Testpunkten des Raspberry Pi
  Zero abgegriffen werden; eine Nutzung der GPIO-Stiftleiste ist nicht
  vorausgesetzt. Fuer Video ist der passende Composite-Pad und die notwendige
  Signalaufbereitung fuer Cinch am konkreten Board zu verifizieren. Als
  Audioausgabe kommen PWM, I2S mit geeignetem DAC oder bei Bedarf ein
  Bluetooth-Audiogeraet in Frage. I2C kann zur Steuerung eines Audiochips
  dienen, ist aber nicht selbst die digitale Audiodatenverbindung.
- Ein Raspberry Pi Pico (RP2040) soll als separates Hilfsboard die
  zeitkritische Ansteuerung der 128x128-HUB75-Matrix uebernehmen. Der
  Raspberry Pi rendert die Konsolen-/PICO-8-Ausgabe und uebertraegt die
  Bilddaten an den Pico. Die Uebertragung soll auf der Pi-Seite moeglichst
  einfach sein. Ob der Pi RGB-Pixel oder PICO-8-Palettenindizes sendet, wird
  beim Prototyp anhand der einfachsten zuverlaessigen Implementierung und
  ausreichenden Bildrate entschieden. Der Pico soll konfigurierbare
  Farbkorrekturen einschliesslich Gamma-Korrektur, Dithering und
  Farbpaletten-Umwandlung ermoeglichen. Palettenprofile koennen beispielsweise
  von Game Boy Color oder Super Game Boy inspiriert sein; es geht um die
  Farbtransformation des PICO-8-Bildes, nicht um Game-Boy-Emulation.
  Die Bilduebertragung und Matrixausgabe sollen asynchron im Hintergrund
  laufen und die PICO-8-Ausfuehrung nicht merklich ausbremsen. Ziel sind
  mindestens 60 aktualisierte Bilder pro Sekunde bei 128x128 Pixeln. Das ist
  auf beiden Pi-Modellen durch Messungen zu verifizieren; insbesondere beim
  Zero W darf die Erreichbarkeit nicht vorausgesetzt werden. Verbindungsart,
  Protokoll, Farbtiefe und Dithering-Verfahren werden beim Hardware-Prototyp
  festgelegt.

## Vorgesehene Ausbaustufen

0. **Buildroot-Basis:** Buildroot-Version 2026.05.3 wird fuer den ersten
   Prototyp fest gepinnt. Die Zielarchitektur ist 32-Bit-ARM mit ARMv6-
   kompatiblem Userspace, damit ein spaeteres Zero-W-Profil moeglich bleibt.
1. **Erster Image-Meilenstein:** Buildroot-Konfiguration fuer den Zero 2 W,
   bootfaehiges SD-Karten-Image, Bootsplash, HDMI-Terminal, Setup-AP mit
   Konfigurationsportal, SSH-Zugang nach WLAN-Einrichtung, A/B-Partitionierung
   mit U-Boot und SWUpdate. Der Update-Zugriff umfasst Web-Upload und Abruf
   von einem Update-Server, Signaturpruefung, Boot-Bestaetigung und Rollback.
   Die Zero-W-Build-Variante folgt nach dem erfolgreichen ersten Boottest.
4. **Konsolenfunktionen:** PICO-8-Laufzeitvoraussetzungen, pixelbasierte
   128x128-Verwaltungsoberflaeche fuer die HUB75-Matrix mit PICO-8-Terminal-
   Layout und pixelbasiertem Monospace-Schriftbild, Controller-Mappings und
   Systemkontrolle; normale Shell fuer Diagnose ueber HDMI und SSH.
5. **Netzwerk, Audio und Speicher:** Erweiterte WLAN-/Bluetooth-Verwaltung,
   Bluetooth-Audio, Koppeln und Verwenden von Gamepads/Joysticks,
   Setup-Access-Point mit QR-Code und Captive Portal, Zeroconf, USB-Speicher
   und Syncthing. Das grundlegende Setup-AP/Portal fuer den Boottest gehoert
   bereits zum Grundsystem.
6. **Bild und Ton:** HUB75-Matrix mit 128x128 Pixeln, angesteuert durch einen
   Raspberry Pi Pico, HDMI-Ausgabe sowie Composite-Video und analoge
   Audioausgabe (PWM, I2S-DAC oder optional Bluetooth) ueber passende
   Pads/Board-Signale bzw. ein gekoppeltes Audiogeraet.

Die Ausbaustufen sind ein Arbeitsvorschlag; Details koennen gemeinsam
angepasst werden. Die Liste beschreibt Anforderungen, keine mitgelieferten
PICO-8-Programme oder -Dateien.

## Vor der Implementierung zu klaeren

- Update-Pakete muessen kryptographisch signiert und vor Installation
  verifiziert werden. Wo der private Signierschluessel liegt, ist noch offen.
- Welcher Webserver bzw. welche Weboberflaeche soll den Update-Upload anbieten?
- Welche Bediengeraete und welche Art Terminal-Eingabe werden fuer den ersten
  Meilenstein benoetigt?
- Welches Bootsplash-Bild soll verwendet werden und wer stellt es bereit?
