# gluon-nightly-build

Dieses Skript erstellt nightly-builds der Gluon-Firmware wenn eine Änderung im GIT-Repository vorliegt. Es werden dabei alle Targets gebaut, die nicht vollständig als "broken" markiert sind.

## Voraussetzung

- Ausgecheckter master-tree vom [Gluon-Repository](https://github.com/freifunk-gluon/gluon)
- Site-Konfiguration im Build-Verzeichnis

## Idee

Mithilfe des Skriptes werden die dynamischen Zonen auf allen DNS-Servern aktualisiert. Es gibt fuer die dynamische Zone keinen primaeren DNS-Server, sondern alle DNS-Server fuehren die Zone selbststaendig. Damit ist der Dienst auch verfuegbar, wenn ein DNS-Server (der ggf. primaerer sonst waere) ausfaellt. Die Gefahr, dass die Zonenstaende ggf. unterschiedlich sind wird dabei in Kauf genommen.

## Nutzung

Das Skript an eine geeignete Stelle kopieren und die Datei gluon-nightly-build.config anlegen.
Als Vorlage fuer die Konfiguration kann die Datei gluon-nightly-build.config.example dienen.

### Konfiguration

In der Konfiguration muessen die folgenden Parameter festgelegt werden:

* Buildroot-Verzeichnis (Verzeichnis in dem der master-tree ausgecheckt wurde
* Mirror-/Webserver-Verzeichnis (Verzeichnis in das die images und module danach per rsync lokal synchronisiert werden)
* Signatur-Schlüssel (Privater Signatur-Schlüssel, der in der site.conf hinterlegt wurde)
* Branch-Name der Firmware
* ggf. Make-Optionen und Aktivierung/Deaktivierung der Images, die sich Status "broken" befinden

### Empfehlung

Das Skript sollte als eingeschränkter Benutzer laufen. In der Beispielkonfiguration wird vom Benutzer "freifunk" ausgegangen.

### Crontab

Folgende Zeile in der Crontab des Benutzers "freifunk" sorgt dafür, dass das Skript jede Nacht automatisiert eine neue Firmware baut (nur wenn GIT-Änderungen vorliegen!) und im Fehlerfall eine E-Mail mit dem Betreff "Fehler im nightly-Build (foo.example.org) und den letzten 100 Zeilen des Build-Logs an foo@example.org sendet. Das Build-Log wird in jedem Fall aufgehoben und beim nächsten Durchlauf überschrieben. Im Erfolgsfall erfolgt keine Meldung.

    0 3 * * * /home/freifunk/gluon-nightly-build/gluon-ightly-build.sh > /tmp/gluon-nightly-build.log 2>&1 || (tail -n 100 /tmp/gluon-nightly-build.log | mail -s "Fehler im nightly-build (build.example.org)" foot@example.org)
