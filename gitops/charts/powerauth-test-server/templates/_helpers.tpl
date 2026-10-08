{{- define "pts.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pts.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "pts.labels" -}}
{{ include "pts.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "pts.secretName" -}}
{{- printf "%s-db" (include "pts.fullname" .) }}
{{- end }}

{{- define "pts.dbEnv" -}}
- name: POWERAUTH_TEST_SERVER_DATASOURCE_URL
  value: {{ printf "jdbc:postgresql://%s:%d/%s?sslmode=%s" (required "database.host is required" .Values.database.host) (int .Values.database.port) .Values.database.name .Values.database.sslMode | quote }}
- name: POWERAUTH_TEST_SERVER_DATASOURCE_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ include "pts.secretName" . }}
      key: username
- name: POWERAUTH_TEST_SERVER_DATASOURCE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "pts.secretName" . }}
      key: password
{{- end }}

{{- define "pts.podSecurityContext" -}}
runAsNonRoot: true
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{- define "pts.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end }}

{{- define "pts.volumes" -}}
- name: tmp
  emptyDir: {}
- name: secrets-store
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: {{ include "pts.fullname" . }}
{{- end }}

{{- define "pts.volumeMounts" -}}
- name: tmp
  mountPath: /tmp
- name: secrets-store
  mountPath: /mnt/secrets-store
  readOnly: true
{{- end }}
