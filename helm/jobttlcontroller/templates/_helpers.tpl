{{/*
Expand the name of the chart.
*/}}
{{- define "jobttlcontroller.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "jobttlcontroller.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "jobttlcontroller.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "jobttlcontroller.labels" -}}
helm.sh/chart: {{ include "jobttlcontroller.chart" . }}
{{ include "jobttlcontroller.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "jobttlcontroller.selectorLabels" -}}
app.kubernetes.io/name: {{ include "jobttlcontroller.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "jobttlcontroller.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "jobttlcontroller.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name
*/}}
{{- define "jobttlcontroller.image" -}}
{{- $registryName := .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" $registryName $tag -}}
{{- end }}

{{/*
Looks up and/or generates certificates for the webhook.
*/}}
{{- define "jobttlcontroller.lookupAndGenerateCerts" -}}
{{- $secretName := printf "%s-cert" (include "jobttlcontroller.fullname" .) -}}
{{- $secret := lookup "v1" "Secret" .Release.Namespace $secretName -}}
{{- if and $secret $secret.data (index $secret.data "ca.crt") (index $secret.data "tls.crt") (index $secret.data "tls.key") }}
  {{- /* Secret exists, use its data */ -}}
  {{- dict "ca" (index $secret.data "ca.crt" | b64dec) "cert" (index $secret.data "tls.crt" | b64dec) "key" (index $secret.data "tls.key" | b64dec) | toYaml -}}
{{- else -}}
  {{- /* Secret does not exist or is incomplete, generate new certs */ -}}
  {{- $ca := genCA (printf "%s-ca" (include "jobttlcontroller.fullname" .)) 3650 -}}
  {{- $fullname := include "jobttlcontroller.fullname" . -}}
  {{- $serviceName := printf "%s-webhook-service" $fullname -}}
  {{- $altNames := list $serviceName (printf "%s.%s" $serviceName .Release.Namespace) (printf "%s.%s.svc" $serviceName .Release.Namespace) (printf "%s.%s.svc.cluster.local" $serviceName .Release.Namespace) -}}
  {{- $cert := genSignedCert $serviceName nil $altNames 3650 $ca -}}
  {{- dict "ca" $ca.Cert "cert" $cert.Cert "key" $cert.Key | toYaml -}}
{{- end -}}
{{- end }}