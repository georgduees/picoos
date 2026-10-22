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
  Die Standardgroesse im kuenftigen Image betraegt 1 GiB (1024 MiB).
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

## A/B-Layout (Entwicklungsimplementierung, Hardwaretest ausstehend)

Der Nutzer hat 1 GiB als Standardgroesse der FAT32-Datenpartition festgelegt.
Die laufende, getestete Karte hat weiterhin 32 MiB Boot, einen 120-MiB-Systemslot
und 256 MiB FAT32-Daten. Die neue Buildkonfiguration implementiert das folgende
Layout, ohne die laufende Karte zu aendern. Boot, Watchdog und Rollback sind
damit noch nicht auf Hardware nachgewiesen.

MBR-Layout mit vier primaeren Partitionen, jeweils
MiB-ausgerichtet:

| Bereich | Start | Groesse | Format | Aufgabe |
| --- | --- | --- | --- | --- |
| Reservierter Anfang | 0 MiB | 1 MiB | MBR und reservierter Rohbereich | Platz fuer redundanten U-Boot-Zustand; nicht als Partition |
| p1 Boot | 1 MiB | 64 MiB | FAT32 | Raspberry-Pi-Firmware, U-Boot und minimales gemeinsames Boot-Setup |
| p2 System A | 65 MiB | 512 MiB | ext4 | Vollstaendiges System A einschliesslich Kernel, DTB und benoetigter Overlays |
| p3 System B | 577 MiB | 512 MiB | ext4 | Vollstaendiges System B einschliesslich Kernel, DTB und benoetigter Overlays |
| p4 Daten | 1089 MiB | 1024 MiB | FAT32 | PICO-8, Cartridges, WLAN-Konfiguration und Nutzerdaten; spaeter bis Kartenende erweiterbar |

512 MiB pro Systemslot ist die Entwicklungsbasis mit Reserve gegenueber dem
aktuellen 120-MiB-System. Nach Klaerung der PICO-8-/SDL-Abhaengigkeiten ist die
Groesse erneut zu pruefen; CI muss zu grosse Slot-Images vor Auslieferung
abweisen. Die Datenpartition bleibt immer die letzte Partition. Ihre spaetere
Erweiterung darf weder Slot-Grenzen noch Bootloader-Zustand veraendern.

### Boot- und Update-Ablauf

1. Die Raspberry-Pi-Firmware startet U-Boot von p1. U-Boot waehlt einen Slot
   und laedt dessen Kernel und passenden Device Tree aus demselben Systemslot.
   Auch benoetigte Overlays gehoeren zur jeweiligen Systemversion; ihre
   Anwendung sowie die Uebernahme der Pi-Firmware-Geraetedaten muessen beim
   U-Boot-Bring-up geprueft werden. Ein gemeinsamer, unabhaengig ersetzter
   Linux-Kernel auf p1 ist fuer normale A/B-Systemupdates nicht vorgesehen.
2. Die Kernel-Kommandozeile benennt die gewaehlte mmcblk0-Root-Partition und
   den Slot eindeutig; Linux prueft dies gegen das tatsaechliche Root-Geraet.
   Fuer den Bring-up bleibt root beschreibbar. Im spaeteren Update-Betrieb
   soll die Root-Partition vorzugsweise nur lesbar sein;
   veraenderliche Systemdateien benoetigen dafuer ein explizites RAM- oder
   persistentes Datenkonzept.
3. SWUpdate prueft die Signatur eines zum Geraeteprofil passenden Pakets und
   schreibt ausschliesslich den inaktiven Systemslot. Das Slot-Image enthaelt
   Rootfs, Kernel, Module, DTB und Overlays als zusammengehoerige Version.
   Der aktive Slot, p1 und die Datenpartition werden dabei nicht beschrieben.
4. Erst nach vollstaendigem Schreiben, Pruefen und Flushen wird der neue Slot
   als Teststart vorgemerkt. Der bisherige Slot bleibt als bestaetigte
   Rueckfallversion erhalten. Ohne vollstaendige Installation erfolgt kein
   Slotwechsel.
5. U-Boot verwendet einen persistenten Versuchszustand und begrenzt die
   Teststarts, als Vorschlag auf drei Versuche. Ein Health-Check bestaetigt
   den neuen Slot erst nach erfolgreichem Start der benoetigten lokalen
   Dienste und Einbindung der Datenpartition. Internet- oder Router-
   Erreichbarkeit darf keine Voraussetzung fuer die Boot-Bestaetigung sein.
   Nach ausbleibender Bestaetigung wird beim naechsten Neustart auf die
   bestaetigte Version zurueckgeschaltet.
6. Fuer ein haengendes System ist zusaetzlich ein getesteter Hardware-Watchdog
   erforderlich: Ein Boot-Zaehler allein startet ein haengendes Geraet nicht
   neu. Redundante U-Boot-Environment-Kopien, konkrete Rohbereich-Offsets und
   die passende SWUpdate-/fw_env-Konfiguration sind gemeinsam festzulegen
   und mit Stromausfalltests zu verifizieren.

Die gemeinsame Pi-Firmware und U-Boot auf p1 sind bei diesem Vorschlag
**nicht A/B-abgesichert**. Ihre Aktualisierung ist ein separater, bewusst
eingeschraenkter Wartungsschritt mit eigenem Wiederherstellungsweg.
Ein normales Systemrollback setzt ausserdem voraus, dass beide Versionen
die persistenten Daten verstehen; Konfigurationsmigrationen muessen deshalb
rueckwaertskompatibel oder gezielt ruecknehmbar bleiben.

### Reihenfolge vor dem Einsatz

U-Boot, SWUpdate mit lokalem Entwicklungsschluessel, vier Partitionen und
p4-Datenverweise sind in der Entwicklungskonfiguration verdrahtet.
Build-/Image-/Signaturtests pruefen die Softwareseite. Anschliessend A/B-Updates, Boot-Bestaetigung,
Watchdog und absichtliche Fehler-/Stromausfallfaelle testen.
Erst nach diesem Layout-Wechsel wird die automatische Datenvergroesserung
implementiert. Ein bestehendes Drei-Partitionen-Image wird nicht im laufenden
Betrieb umpartitioniert; der Wechsel erfolgt mit Sicherung und Neu-Flashen.

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
