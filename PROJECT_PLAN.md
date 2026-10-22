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
  werden. Fuer die vorliegende Version 0.2.7 benoetigt `pico8_dyn` SDL2;
  SDL2 wurde deshalb zur Buildroot-Konfiguration hinzugefuegt. Die
  Kompatibilitaet der SDL2-Grafik-/Audio-/Eingabe-Backends, der HDMI-Ausgabe
  und die Leistung auf Zero 2 W und dem aelteren Zero W muessen praktisch
  geprueft werden. Das klassische `pico8` benoetigt das im Image fehlende
  Legacy-`libbcm_host.so`, `pico8_gpio` zusaetzlich WiringPi, und die
  64-Bit-Variante passt nicht zum 32-Bit-Userspace.
- Als lokale Installationsquelle liegt `pico8/pico-8_0.2.7_raspi.zip` vor.
  Das Archiv enthaelt 32-Bit-ARM-Varianten (`pico8`, `pico8_dyn`,
  `pico8_gpio`) und eine 64-Bit-AArch64-Variante (`pico8_64`). Das zum
  Zielsystem passende Binary soll bei der Provisionierung auf die
  Datenpartition installiert werden; PICO-8 bleibt ausserhalb des
  Buildroot-Systemimages.
- Bluetooth soll Audioausgabe sowie das Koppeln und Verwenden von Gamepads,
  Joysticks und vergleichbaren Eingabegeraeten unterstuetzen.
- Fuer die Eingabeunterstuetzung sind BlueZ mit `bluetoothctl`, HID/HOG,
  Kernel-HCI-UART-/HID-/evdev-/joydev-Treiber und SDL2-Joystick-Unterstuetzung
  im Zero-2-W-Build aktiviert. Der Kernel reserviert vier 8250-UART-Linien,
  damit die interne Bluetooth-Mini-UART auf Linie 1 registriert werden kann.
  Zusaetzlich wird `core_freq=250` in der gemeinsamen Firmwarekonfiguration
  gesetzt, damit die Mini-UART-Baudrate fuer den Bluetooth-Betrieb stabil
  bleibt. Da der Kernel-Serdev-Attach auf diesem Ziel bisher beim BCM-
  Firmwarehandshake in Timeouts lief, wird als Fallback ein expliziter
  `btattach`-Start vor `bluetoothd` eingeplant.
  Die BlueZ-Pairings werden auf der FAT32-
  Datenpartition gespeichert, damit sie A/B-Systemupdates ueberleben.
  Controller-Erkennung, echtes Pairing und SDL-Eingaben sind noch am Geraet zu
  testen; Bluetooth-Audio braucht noch einen festgelegten ALSA-/Audio-Backendpfad.
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

## A/B-Layout (A/B-Starts, Watchdog-Rollback und SWUpdate in beide Richtungen getestet)

Der Nutzer hat 1 GiB als Standardgroesse der FAT32-Datenpartition festgelegt.
Die bisherige Drei-Partitionen-Karte hatte 32 MiB Boot, einen
120-MiB-Systemslot und 256 MiB FAT32-Daten. Die neue Buildkonfiguration
implementiert das folgende Layout. Die Karte wurde nach gepruefter Sicherung ausdruecklich fuer den
Hardwaretest neu geschrieben. Der erste Slot-A-Boot mit p4-Daten, WLAN,
Ethernet-SSH, lokaler Bestaetigung und aktivem Watchdog ist nach der
Firmware-UART-Korrektur nachgewiesen. Nach Korrektur eines Rueckgabewertfehlers
im alten U-Boot-Hush-Parser starten und bestaetigen sich A und B.
Drei unbestaetigte A-Starts mit Zaehler 1/2/3, automatische Watchdog-Neustarts
und Rueckfall auf bestaetigtes B wurden getestet. Der voruebergehend
deaktivierte A-Health-Check wurde wiederhergestellt und ein normaler
Rueckstart nach A bestaetigt. Alle 12 Nutzdateien blieben hashgleich.
Eine echte signierte SWUpdate-Installation von A nach B mit vollstaendigem
512-MiB-Readback, Neustart und automatischer Bestaetigung von B ist ebenfalls
getestet. Manipulierte Pakete sowie falsches Board/Revision wurden vom echten
SWUpdate auf dem Pi abgewiesen. Der private Ethernet-/Schluessel-SSH-Zugang
wurde nach dem Raw-Schreiben ausdruecklich als Testprovisionierung in B
wiederhergestellt; dauerhafte Konfigurationspersistenz ist damit nicht geloest.
B lief danach laenger als 90 Sekunden mit aktivem Watchdog, WLAN und
unveraenderten 12 Nutzdateien. Anschliessend wurde auch die echte Gegenrichtung
B nach A ausdruecklich freigegeben und getestet: vollstaendiger 512-MiB-Readback,
vor Neustart wiederhergestellter Diagnosezugang und automatische Bestaetigung
von A. A blieb laenger als 90 Sekunden im selben Boot mit aktivem Watchdog,
WLAN und SSH erreichbar. Alle 12 Nutzdateien und die gemeinsame Bootpartition
blieben hashgleich. Nach diesem Test war A bestaetigt; Zaehler und Upgrade-Marker
waren 0.
Beliebige Kernel-Haenger und Stromausfalltests sind noch offen.
CI-Lauf 39805575018 (Buildroot, Diagnose-, WLAN-, A/B- und FAT32-Tests)
ist erfolgreich. Der gemeinsame p1-U-Boot wurde danach kontrolliert durch
den Build mit abgeschaltetem VIDEO_LOGO/SPLASH_SCREEN ersetzt; Video- und
serielle Textkonsole bleiben aktiv. Nur u-boot.bin wurde atomar ersetzt;
Firmwareconfig/UART, redundante Environment, beide Roots und /data blieben
unangetastet. Ein exaktes 64-MiB-Rohbackup von p1 liegt geprueft auf /data und
zusaetzlich lokal unter provisioning/local/backups. Der neue Bootloader startete
erfolgreich in bestaetigtes A; Persistenz, Watchdog und WLAN funktionieren.
Aktuell ist A bestaetigt. Keine unabhaengige HDMI-Aufnahme zur visuellen
Logo-Pruefung; der Linux-Bootsplash ist unveraendert.

**Explizite Diagnosepersistenz:**

Auf Nutzerwunsch bleibt der regulaere `pico`-Account ein eigener Schritt.
Der temporaere Root-Diagnosezugang ist stattdessen ausdruecklich aktivierbar:
`picoos-diagnostics enable PUBLIC_KEY [HOST_KEY]` speichert nur Ed25519-
Autorisierungsschluessel, Hostschluessel und einen versionierten Freigabemarker
unter `/data/diagnostics`. Ohne Freigabe startet kein Root-SSH-Listener.
Die FAT32-Dateien sind unter Linux root-exklusiv, aber physisch unverschluesselt
lesbar. Private Daten bleiben ausserhalb von Git und oeffentlichen Images.

Vor Netzwerkstart werden die Schluessel geprueft und mit echten 0600-Rechten
ins RAM kopiert. Ethernet-DHCP/ASIX und Avahi passen zum Diagnosezugang;
Dropbear nutzt feste Schluessel-only-Argumente. Bei aktivierter Diagnose
verlangt der lokale Boot-Health-Check auch den laufenden SSH-Dienst.
Die einmalige Offline-Provisionierung importiert nur bei fehlendem Daten-
Store; bestehende persistente Einstellungen haben Vorrang.
Das ist kein allgemeiner Import beliebiger Root-Konfiguration und aktiviert
nicht automatisch den Basis-Public-Key als Root-Schluessel.

Der anschliessende Hardwaretest ist bestanden: Die vorhandenen Diagnose-
Schluessel wurden ausdruecklich auf `/data` aktiviert und alle 15 Dateien
privat gesichert und verifiziert. Lokal aus dem letzten CI-Root und den neuen Overlay-Dateien zusammengesetzte,
gepruefte und signierte Root-Testpakete wurden per echtem SWUpdate sowohl nach
B als auch mit der korrigierten Hostschluessel-Erzeugung nach A installiert.
Beide Rohimages wurden vollstaendig zurueckgelesen; beide Slots wurden danach
nur lesend kontrolliert, nicht mit privaten Dateien nachprovisioniert.
Nach Neustart richteten sie SSH/Ethernet selbst aus den persistenten Daten ein
und bestaetigten sich. Hostidentitaet, Schluessel-only-Anmeldung, RAM-Rechte
0600, Watchdog, WLAN sowie unveraenderte 15 Dateien und p1 sind nachgewiesen.
Aktuell ist A bestaetigt, B bleibt als vorheriger persistenter Root-Slot
erhalten. Der vollstaendige CI-Neubau 39805575018 ist inzwischen erfolgreich;
die lokal assemblierten Root-Images fuer den Hardwaretest sind davon getrennt.
Allgemeine System-/pico-Konfiguration ist noch nicht persistent umgesetzt.

Der U-Boot ohne eigenes Logo/Splash aus diesem CI-Artefakt wurde danach
kontrolliert auf p1 installiert. Ein hashverifiziertes, exakt 64-MiB grosses
Rohbackup der vorherigen Bootpartition liegt sowohl auf `/data` als auch
ausgelagert unter `provisioning/local/backups/bootloader-20261022.*`.
Nur `u-boot.bin` auf p1 wurde ersetzt; nach Neustart startete und bestaetigte
sich A, persistenter SSH-Zugang, Watchdog, WLAN und Nutzdaten blieben intakt.
Das Wiederherstellungsskript `scripts/restore-picoos-boot-partition.sh`
schreibt nach Layout-/Hashpruefung ausschliesslich p1 zurueck.
Die Textkonsole bleibt konfiguriert; eine externe HDMI-Aufnahme gibt es nicht.

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
   Der aktive Slot und p1 sind keine Installationsziele des Raw-Handlers.
   Nutzdateien auf der Datenpartition werden nicht ersetzt; dort werden
   voruebergehend private Update-Arbeitsdateien angelegt und wieder entfernt.
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
