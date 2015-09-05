# ICVPN-dns-update

Dieses Skript aktualisiert die ICVPN-DNS-Zonen und ist zum Einsatz als Cronjob gedacht. Es verwendet das Skript mkdns aus dem Repository icvpn-scripts. Es prueft die ICVPN-Repositories und aktualisiert die DNS-Konfiguration, wenn sich etwas aendert. Aenderungen am Repository icvpn-scripts werden ebenfalls geprueft und es erfolgt eine entsprechende Ausgabe, wenn ein neuer Commit erfolgt ist. Die Aktualisierung der Scripte erfolgt aus Sicherheitsgruenden aber nicht automatisch.

## Nutzung

Das Skript an eine geeignete Stelle kopieren und die Datei icvpn-dns-update.config anlegen.
Als Vorlage fuer die Konfiguration kann die Datei icvpn-dns-update.config.example dienen.

### Konfiguration

In der Konfiguration muessen die folgenden Parameter festgelegt werden:

* Art des DNS-Servers
* Konfigurationsdatei (die vom DNS-Server importiert wird)
* eigene Community (damit eigene Zonen nicht mit integriert werden)

### Ersteinrichtung

Da das Skript auf mkdns aufsetzt muss das icvpn-scripts-Repository in dem Verzeichnis existieren, in dem icvpn-dns-update.sh liegt. Das Repository wird bei der ersten Nutzung geklont.

### Aktualisierung des icvpn-script-Repository

Wenn im icvpn-script-Repository Aenderungen vorgenommen werden, dann gibt das Skript fuer jeden Commit einmalig eine Ausgabe. Cron sollte also in der Lage sein, dies per Mail zu versenden. Die letzte Commit-ID fuer die eine Benachrichtigung erfolgte wird in icvpn-dns-update.scripts-commit-id im Skriptverzeichnis gespeichert.

Im Skript-Verzeichnis existiert ein Verzeichnis "icvpn-scripts". In diesem Verzeichnis kann man dann mit

* git pull

das icvpn-scripts-Repository aktualisieren.

### Temporaere Daten

Die icvpn-Repositories werden in /tmp/icvpn-git geklont und aktualisiert. Dort werden auch die Aenderungen verfolgt. Wenn das Verzeichnis (z.B. nach Neustart) nicht mehr existiert, dann wird es automatisch wieder angelegt.

### Cronjob

    # Recreate ICVPN dns config
    23 *    * * *	root	/usr/local/bin/icvpn/dns-update/icvpn-dns-update.sh

### DNS reload/restart

Fuer bind und unbound erfolgt ein Reload der Konfiguration nach Aktualisierung der Zonendatei. dnsmasq wird bei Aktualisierung neugestartet.
