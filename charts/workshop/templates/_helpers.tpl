{{/*
Resource names are fixed rather than release-scoped: JupyterHub's chart is a
subchart, its values cannot be templated, and it must reference these objects
by name. One workshop per namespace is the trade that buys that simplicity.
*/}}
{{- define "workshop.rosterSecret" -}}workshop-roster{{- end -}}
{{- define "workshop.authenticatorConfigMap" -}}workshop-roster-auth{{- end -}}
{{- define "workshop.participantServiceAccount" -}}workshop-participant{{- end -}}

{{- define "workshop.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
