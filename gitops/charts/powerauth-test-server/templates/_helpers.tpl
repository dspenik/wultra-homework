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

{{- define "pts.useKeyVault" -}}
{{- if eq .Values.secrets.source "keyvault" }}true{{- else if eq .Values.secrets.source "existing" }}{{- else }}{{- fail "secrets.source must be 'keyvault' or 'existing'" }}{{- end }}
{{- end }}

{{- define "pts.secretName" -}}
{{- if include "pts.useKeyVault" . }}
{{- printf "%s-db" (include "pts.fullname" .) }}
{{- else }}
{{- required "secrets.existingSecret is required when secrets.source=existing" .Values.secrets.existingSecret }}
{{- end }}
{{- end }}

{{- define "pts.podLabels" -}}
{{- if include "pts.useKeyVault" . }}
azure.workload.identity/use: "true"
{{- end }}
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
{{- if include "pts.useKeyVault" . }}
- name: secrets-store
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: {{ include "pts.fullname" . }}
{{- end }}
{{- end }}

{{- define "pts.volumeMounts" -}}
- name: tmp
  mountPath: /tmp
{{- if include "pts.useKeyVault" . }}
- name: secrets-store
  mountPath: /mnt/secrets-store
  readOnly: true
{{- end }}
{{- end }}
