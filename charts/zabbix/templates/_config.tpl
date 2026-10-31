{{/*
The ConfigMaps' data, as helpers: ConfigMaps.yaml renders them, and each Deployment hashes its own
into checksum/config. Hashing the content rather than the rendered ConfigMap keeps the labels, and
with them the chart version, out of the checksum: a release that changes nothing a pod reads does
not restart it. Both validate first, so a refusal reads the same from whichever template runs it.
*/}}

{{- define "zabbix.serverConfigData" -}}
{{- include "zabbix.validate" . }}
{{- $db := .Values.database }}
# The image ships no entrypoint to render this from environment variables, so it is rendered
# here. DBPassword is not in it: the server takes the password nowhere but this file, so the
# `config` init container appends it from the Secret into a copy on a memory-backed volume.
# Keeping it out of here keeps it out of the ConfigMap and out of `helm get manifest`.
zabbix_server.conf: |
  ListenPort={{ .Values.service.server }}
  DBHost={{ $db.host }}
  DBPort={{ $db.port }}
  DBName={{ $db.name }}
  DBUser={{ $db.user }}
  {{- range $key, $value := .Values.server.config }}
  {{ $key }}={{ $value }}
  {{- end }}
  {{- with .Values.server.extraConfig }}
  {{ . | nindent 2 | trim }}
  {{- end }}
{{- end }}

{{- define "zabbix.webConfigData" -}}
{{- include "zabbix.validate" . }}
{{- $db := .Values.database }}
# nginx hands .php to php-fpm beside it in the same pod, so the address is the loopback: no
# Service, and nothing else on the network can reach the FastCGI port.
default.conf: |
  server {
      listen 8080;
      server_name _;
      root /usr/share/zabbix;
      index index.php;

      gzip on;
      gzip_static on;

      location = /ping {
          access_log off;
          default_type text/plain;
          return 200 "pong\n";
      }

      location /assets {
          expires 10d;
      }

      location ~ \.php$ {
          fastcgi_pass 127.0.0.1:9000;
          fastcgi_index index.php;
          fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
          include fastcgi_params;
          fastcgi_read_timeout 300;
      }

      location ~ /\.ht {
          deny all;
      }
  }

# The frontend's own configuration. Without it the frontend offers its installation wizard, so
# a pod that lost this ConfigMap is obvious rather than subtly wrong. The password is read from
# the projected Secret rather than written here.
zabbix.conf.php: |
  <?php
  $DB['TYPE']     = 'POSTGRESQL';
  $DB['SERVER']   = '{{ $db.host }}';
  $DB['PORT']     = '{{ $db.port }}';
  $DB['DATABASE'] = '{{ $db.name }}';
  $DB['USER']     = '{{ $db.user }}';
  $DB['PASSWORD'] = trim(file_get_contents('/run/secrets/database/password'));
  $DB['SCHEMA']   = '';
  $ZBX_SERVER      = '{{ include "zabbix.componentName" (list . "server") }}';
  $ZBX_SERVER_PORT = '{{ .Values.service.server }}';
  $ZBX_SERVER_NAME = '{{ include "zabbix.fullname" . }}';
  $IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
  {{- with .Values.web.extraConfig }}
  {{ . | nindent 2 | trim }}
  {{- end }}

# php-fpm reads its timezone from the ini files it scans, not from the pool
zabbix-php.ini: |
  date.timezone = {{ .Values.web.timezone }}
{{- end }}
