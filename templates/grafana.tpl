{{- $app := index .Values "app-chart" -}}

{{- if and $app.metrics.grafana.enabled
          $app.metrics.grafana.dashboard.enabled
          $app.metrics.grafana.dashboard.items }}

{{- $items := $app.metrics.grafana.dashboard.items -}}

{{- range $key, $item := $items }}

  {{- if $item.enabled }}

    {{- $path := printf "files/%s.json" $key -}}
    {{- $content := $.Files.Get $path -}}

    {{- if not $content }}
      {{- fail (printf "Grafana dashboard file not found: %s" $path) -}}
    {{- end }}

    {{- /* Inject JSON into values */ -}}
    {{- $_ := set $item "json" $content -}}

  {{- end }}

{{- end }}

{{- /* Now render using updated values */ -}}
{{- include "libChart.classes.grafana" (dict
      "Values" $app
      "Release" .Release
      "Chart" .Chart
      "Capabilities" .Capabilities
      "Template" .Template
  ) -}}

{{- end }}
