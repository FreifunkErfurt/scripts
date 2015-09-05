# dns2dhcp

Dieses Skript aktualisiert dynamische Bind-Zonen bei Vergabe von IPv4-Adressen durch den DHCP-Server. Es benötigt bind und dhcpd.

## Idee

Mithilfe des Skriptes werden die dynamischen Zonen auf allen DNS-Servern aktualisiert. Es gibt fuer die dynamische Zone keinen primaeren DNS-Server, sondern alle DNS-Server fuehren die Zone selbststaendig. Damit ist der Dienst auch verfuegbar, wenn ein DNS-Server (der ggf. primaerer sonst waere) ausfaellt. Die Gefahr, dass die Zonenstaende ggf. unterschiedlich sind wird dabei in Kauf genommen.

## Nutzung

Das Skript an eine geeignete Stelle kopieren und die Datei dhcp2dns.config anlegen.
Als Vorlage fuer die Konfiguration kann die Datei dhcp2dns.config.example dienen.

### Konfiguration

In der Konfiguration muessen die folgenden Parameter festgelegt werden:

* DNS-Server
* DHCP-Ranges
* Domain
* Oktette fuer Reverse-Zone
* TTL des Eintrages

### Integration in dhcpd

/etc/dhcp/dhcpd.conf:

    subnet 10.99.0.0 netmask 255.255.192.0 {
        ...
        on commit {
          set client_ip = binary-to-ascii(10, 8, ".", leased-address);
          set clientName = pick-first-value ( option fqdn.hostname, option host-name );
          execute("/usr/local/bin/dhcp2dns/dhcp2dns.sh", "-a -i", client_ip, "-n", clientName);
        }

        on release {
          set client_ip = binary-to-ascii(10, 8, ".", leased-address);
          set clientName = pick-first-value ( option fqdn.hostname, option host-name );
          execute("/usr/local/bin/dhcp2dns/dhcp2dns.sh", "-d -i", client_ip, "-n", clientName);
        }

        on expiry {
          set client_ip = binary-to-ascii(10, 8, ".", leased-address);
          set clientName = pick-first-value ( option fqdn.hostname, option host-name );
          execute("/usr/local/bin/dhcp2dns/dhcp2dns.sh", "-d -i", client_ip, "-n", clientName);
        }
    }

### Integration in bind

/etc/bind/named.conf.local:

    acl "dns_server" {
        // Interne IPs der Freifunk-DNS-Server
        10.99.1.2;
        10.99.1.3;
    };

    zone "dyn.ffef" IN {
        type master;
        file "/etc/bind/dyn.ffef.zone";
        notify no;
        allow-update {
                dns_server;
        };
    };

    zone "12.99.10.in-addr.arpa" IN {
        type master;
        file "/etc/bind/12.99.10.in-addr.arpa.zone";
        notify no;
        allow-update {
                dns_server;
        };
    };
    ...
    zone "19.99.10.in-addr.arpa" IN {
        type master;
        file "/etc/bind/12.99.10.in-addr.arpa.zone";
        notify no;
        allow-update {
                dns_server;
        };
    };
