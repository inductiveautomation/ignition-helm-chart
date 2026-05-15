{{/*
Expand the name of the chart.
*/}}
{{- define "ignition.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "ignition.fullname" -}}
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
{{- define "ignition.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "ignition.labels" -}}
helm.sh/chart: {{ include "ignition.chart" . }}
{{ include "ignition.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "ignition.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ignition.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "ignition.serviceAccountName" -}}
  {{- if .Values.serviceAccount.create }}
    {{- default (include "ignition.fullname" .) .Values.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/*
Produce fully-qualified image reference for Ignition.
*/}}
{{- define "ignition.image-reference" -}}
{{- printf "%s/%s:%s" .Values.image.registry 
                      .Values.image.repository
                      (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
Fails rendering if the input is not a number of either:
- a plain integer or decimal (e.g. 123, 123.4)
- a number with scientific notation (e.g. 12e3, 1.2e3, 1.2e+03)
*/}}
{{- define "ignition.failIfNotNumber" -}}
  {{- $input := . | toString | trim -}}
  {{- $matches := (list 
    "^[0-9]+(\\.[0-9]+)?$"
    "^[0-9]+(\\.[0-9]+)?[eE][+-]?[0-9]+$"
  ) -}}
  {{- $isNumber := false -}}
  {{- range $regex := $matches -}}
    {{- if regexMatch $regex $input -}}
      {{- $isNumber = true -}}
      {{- break -}}
    {{- end -}}
  {{- end -}}
  {{- if not $isNumber -}}
    {{- fail (printf "Invalid value (%s): must be a number" $input) -}}
  {{- end -}}
{{- end -}}

{{/*
Accepts a Kubernetes memory quantity value (e.g. Mi, Gi, etc) and emits the representative byte count
*/}}
{{- define "ignition.memoryLimitToBytes" -}}
  {{- $input := . | toString | trim -}}
  {{- $units := list
    (dict "suffix" "Ei" "factor" 1152921504606846976.0)
    (dict "suffix" "Pi" "factor" 1125899906842624.0)
    (dict "suffix" "Ti" "factor" 1099511627776.0)
    (dict "suffix" "Gi" "factor" 1073741824.0)
    (dict "suffix" "Mi" "factor" 1048576.0)
    (dict "suffix" "Ki" "factor" 1024.0)
    (dict "suffix" "E" "factor" 1e18)
    (dict "suffix" "P" "factor" 1e15)
    (dict "suffix" "T" "factor" 1e12)
    (dict "suffix" "G" "factor" 1e9)
    (dict "suffix" "M" "factor" 1e6)
    (dict "suffix" "k" "factor" 1e3)
  -}}
  {{- $matched := false -}}

  {{- /* Suffixed units: e.g. 1536Mi, 1.5Gi */ -}}
  {{- range $unit := $units -}}
    {{- $suffix := get $unit "suffix" -}}
    {{- if and (not $matched) (hasSuffix $suffix $input) -}}
      {{- $n := $input | trimSuffix $suffix -}}
      {{- include "ignition.failIfNotNumber" $n -}}
      {{- mulf ($n | float64) (get $unit "factor") | int64 | toString -}}
      {{- $matched = true -}}
    {{- end -}}
  {{- end -}}

  {{- if not $matched -}}
    {{- /* Milli-bytes: e.g. 1500m */ -}}
    {{- if hasSuffix "m" $input -}}
      {{- $n := $input | trimSuffix "m" -}}
      {{- include "ignition.failIfNotNumber" $n -}}
      {{- divf ($n | float64) 1000.0 | ceil | int64 | toString -}}

    {{- /* Scientific notation */ -}}
    {{- else if contains "e" $input -}}
      {{- include "ignition.failIfNotNumber" $input -}}
      {{- $input | float64 | int64 | toString -}}

    {{- /* Plain integer or decimal */ -}}
    {{- else -}}
      {{- if not (regexMatch "^[0-9]+(\\.[0-9]+)?$" $input) -}}
        {{- fail "Invalid value for memory limit: must be a valid memory quantity" -}}
      {{- end -}}
      {{- $input | float64 | int64 | toString -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Returns "true" if .Values.gateway.maxRAMPercentage should be used
*/}}
{{- define "ignition.gateway.useMaxRAMPercentage" -}}
  {{- $maxRAMValueValid := false -}}
  {{- if (kindIs "string" .Values.gateway.maxRAMPercentage) -}}
    {{- if (eq .Values.gateway.maxRAMPercentage "auto") -}}
      {{- $maxRAMValueValid = true -}}
    {{- else -}}
      {{- fail "Invalid value for gateway.maxRAMPercentage: must be 'auto' or a number" -}}
    {{- end -}}
  {{- else -}}
    {{- $maxRAMValueValid = (gt (.Values.gateway.maxRAMPercentage | int) 0) -}}
  {{- end -}}
  {{- $resourcedEnabled := .Values.gateway.resourcesEnabled -}}
  {{/* Bring the computed resources into an object, defaulting to an empty dictionary */}}
  {{- $resources := fromYaml (include "ignition.gateway.resources" .) | default dict -}}
  {{/* Check if resources.limits.memory is set */}}
  {{- $resourcesMemoryLimitsExists := not (empty (dig "resources" "limits" "memory" "" $resources)) -}}
  {{- printf "%t" (and $maxRAMValueValid $resourcedEnabled $resourcesMemoryLimitsExists) }}
{{- end }}

{{/*
Emits a numeric value for the max RAM percentage for JVM heap; if set to "auto", will dynamically compute a
value based on the applied memory resource limits.
Assumes that "ignition.gateway.useMaxRAMPercentage" has already been checked.
*/}}
{{- define "ignition.gateway.maxRAMPercentage" -}}
  {{- $maxRAMPercentage := .Values.gateway.maxRAMPercentage | default "auto" -}}

  {{- /* Normalize to a string to unblock comparison */ -}}
  {{- $maxRAMPercentage := $maxRAMPercentage | toString -}}
  {{- if (eq $maxRAMPercentage "auto") -}}
    {{- $resources := fromYaml (include "ignition.gateway.resources" .) | default dict -}}
    {{- $memoryLimitBytes := (include "ignition.memoryLimitToBytes" (dig "resources" "limits" "memory" "1536Mi" $resources)) | int64 -}}
    {{- if (le $memoryLimitBytes 4294967296) -}}
      {{- $maxRAMPercentage = 50 -}}
    {{- else if (le $memoryLimitBytes 6442450944) -}}
      {{- $maxRAMPercentage = 60 -}}
    {{- else if (le $memoryLimitBytes 8589934592) -}}
      {{- $maxRAMPercentage = 70 -}}
    {{- else if (le $memoryLimitBytes 17179869184) -}}
      {{- $maxRAMPercentage = 80 -}}
    {{- else -}}
      {{- $maxRAMPercentage = 85 -}}
    {{- end -}}
  {{- end -}}

  {{- printf "%v" $maxRAMPercentage }}
{{- end }}

{{/*
Emits a numeric value for the initial RAM percentage for JVM heap.  Defaults to the same value as max RAM percentage.
Assumes that "ignition.gateway.useMaxRAMPercentage" has already been checked.
*/}}
{{- define "ignition.gateway.initialRAMPercentage" -}}
  {{- $maxRAMPercentage := (include "ignition.gateway.maxRAMPercentage" .) -}}
  {{- $initialRAMPercentage := .Values.gateway.initialRAMPercentage | default "auto" -}}

  {{- if (kindIs "string" $initialRAMPercentage) -}}
    {{- if (eq $initialRAMPercentage "auto") -}}
      {{- $initialRAMPercentage = $maxRAMPercentage -}}
    {{- else -}}
      {{- fail "Invalid value for gateway.initialRAMPercentage: must be 'auto' or a number" -}}
    {{- end -}}
  {{- else -}}
    {{- $initialRAMPercentage = (min $initialRAMPercentage $maxRAMPercentage) -}}
  {{- end -}}

  {{- printf "%v" $initialRAMPercentage }}
{{- end }}

{{/*
Emit the array elements for Ignition JVM args.
*/}}
{{- define "ignition.gateway.jvmArgs" -}}
  {{- /* Default JVM Args */ -}}
  {{- $jvmArgs := list }}
  {{- if eq "true" (include "ignition.gateway.useMaxRAMPercentage" .) -}}
    {{- $maxRAMPercentage := ((include "ignition.gateway.maxRAMPercentage" .) | int) -}}
    {{- $initialRAMPercentage := ((include "ignition.gateway.initialRAMPercentage" .) | int) -}}
    {{- $jvmArgs = append $jvmArgs (printf "%s=%v" "-XX:InitialRAMPercentage" $initialRAMPercentage) -}}
    {{- $jvmArgs = append $jvmArgs (printf "%s=%v" "-XX:MaxRAMPercentage" $maxRAMPercentage) -}}
    {{- with .Values.gateway.maxDirectMemorySize }}
    {{- $jvmArgs = append $jvmArgs (printf "%s=%v" "-XX:MaxDirectMemorySize" .) -}}
    {{- end }}
  {{- end -}}
  {{- if eq "true" (include "ignition.gateway.licensing.leasedActivation.terminateSessionOnShutdown" .) -}}
    {{- $terminateSessionSysProp := "-Dignition.license.leased-activation-terminate-sessions-on-shutdown=true" -}}
    {{- if not (has $terminateSessionSysProp .Values.gateway.jvmArgs) -}}
      {{- $jvmArgs = append $jvmArgs $terminateSessionSysProp -}}
    {{- end -}}
  {{- end -}}
  {{- with .Values.gateway.loggers -}}
  {{- $jvmArgs = append $jvmArgs (printf "%s=%s" "-Dlogback.configurationFile" "/config/files/logback.xml") -}}
  {{- end -}}
  {{- with .Values.gateway.deploymentMode -}}
  {{- $jvmArgs = append $jvmArgs (printf "%s=%s" "-Dignition.config.mode" .) -}}
  {{- end -}}
  {{- $jvmArgs = concat $jvmArgs (.Values.gateway.jvmArgs | default list) -}}
  {{- range $i, $jvmArg := $jvmArgs }}
    {{- /* JVM args have less structure, so we're just dumping the list here */ -}}
      {{- printf "\n- %v" $jvmArg }}
  {{- end }}
{{- end }}

{{/*
Emit the array elements for Ignition Gateway args.
*/}}
{{- define "ignition.gateway.gatewayArgs" -}}
  {{- /* Default Gateway Args */ -}}
  {{- $gatewayArgs := dict -}}
  {{- $useProxyForwardedHeader := (include "ignition.ingress.useProxyForwardedHeader" .) -}}
  {{- $_ := set $gatewayArgs "useProxyForwardedHeader" $useProxyForwardedHeader -}}
  {{- /* Manual merge to workaround bool-merge issue */ -}}
  {{- range $key, $value := (.Values.gateway.gatewayArgs | default dict) }}
    {{- $_ := set $gatewayArgs $key $value -}}
  {{- end }}

  {{- range $key, $value := $gatewayArgs }}
    {{- /* Render list items with $key=$value */ -}}
      {{- printf "\n- gateway.%s=%v" $key $value }}
  {{- end }}
{{- end }}

{{/*
Emit the array elements for Ignition Wrapper args.
*/}}
{{- define "ignition.gateway.wrapperArgs" -}}
  {{- /* Default Wrapper Args */ -}}
  {{- $wrapperArgs := dict -}}
  {{- if eq "true" (include "ignition.gateway.useMaxRAMPercentage" .) -}}
  {{- $_ := set $wrapperArgs "wrapper.java.initmemory" "0" -}}
  {{- $_ := set $wrapperArgs "wrapper.java.maxmemory" "0" -}}
  {{- end -}}
  {{- $wrapperArgs := merge (.Values.gateway.wrapperArgs | default dict) $wrapperArgs -}}
  {{- range $key, $value := $wrapperArgs }}
    {{- /* Render list items with $key=$value */ -}}
      {{- printf "\n- %s=%v" $key $value }}
  {{- end }}
{{- end }}

{{/*
Collect and emit all of the Ignition image "command" args.
*/}}
{{- define "ignition.gateway.supplementalArgs" -}}
  {{- include "ignition.gateway.wrapperArgs" . }}
  {{- include "ignition.gateway.gatewayArgs" . }}
  {{- include "ignition.gateway.jvmArgs" . }}
{{- end }}

{{/*
Emit the array elements for setting the Ignition System Name via runtime args.
*/}}
{{- define "ignition.gateway.systemNameArgs" -}}
  {{- if eq "true" (include "ignition.gateway.useIndexedSystemName" .) }}
- -n
- {{ printf "%s-%s" (.Values.gateway.systemNameOverride | default (include "ignition.fullname" . )) "$(GATEWAY_POD_INDEX)" }}
  {{- else }}
- -n
- {{ .Values.gateway.systemNameOverride | default (include "ignition.fullname" . ) }}
  {{- end }}
{{- end }}

{{/*
Return true or false (string) based on our logic for using a pod index as suffix on gateway name.
*/}}
{{- define "ignition.gateway.useIndexedSystemName" -}}
  {{- $replicasAreOne := (eq (.Values.gateway.replicas | default 1 | int) 1) }}
  {{- if .Values.gateway.redundancy.enabled }}
    {{- printf "%v" false }}
  {{- else if (eq false .Values.gateway.systemNameUseIndexed) -}}
    {{- printf "%v" false }}
  {{- else if (and (not .Values.gateway.systemNameUseIndexed) $replicasAreOne) -}}
    {{- printf "%v" false }}
  {{- else }}
    {{- printf "%v" true }}
  {{- end }}
{{- end }}

{{/*
Emit the array elements for driving the public address settings via runtime args.
*/}}
{{- define "ignition.gateway.publicAddressArgs" -}}
  {{- $args := dict }}
  {{- $autoDetect := ((get .Values.gateway.publicAddress "autoDetect") | default false) }}
  {{- $hostFQDN := (include "ignition.ingress.hostName" (list . "")) }}

  {{- /* Initialize args with public address if ingress is enabled */ -}}
  {{- if (and .Values.ingress.enabled (not $autoDetect)) }}
    {{- $_ := set $args "-a" $hostFQDN }}
    {{- $_ := set $args "-h" 80 }}
    {{- $_ := set $args "-s" 443 }}
  {{- end }}

  {{- /* Override public address args defaults, if defined */ -}}
  {{- if (not $autoDetect) }}
  {{- with .Values.gateway.publicAddress }}
    {{- $host := .host | default $hostFQDN }}
    {{- $httpPort := .http | default 80 }}
    {{- $httpsPort := .https | default 443 }}
    {{- $_ := set $args "-a" $host }}
    {{- $_ := set $args "-h" $httpPort }}
    {{- $_ := set $args "-s" $httpsPort }}
  {{- end }}
  {{- end }}

  {{- /* Only emit if redundancy is disabled.  When enabled, these are handled by igniton.gateway.publicAddressEnvs */ -}}
  {{- if not .Values.gateway.redundancy.enabled }}
  {{- range $arg, $value := $args }}
    {{- printf "\n- %s" $arg }}
    {{- printf "\n- %s" ($value | quote) }}
  {{- end }}
  {{- end }}
{{- end }}

{{/*
Collect and emit the system name and public address runtime args.
*/}}
{{- define "ignition.gateway.runtimeArgs" -}}
  {{- include "ignition.gateway.systemNameArgs" . }}
  {{- include "ignition.gateway.publicAddressArgs" . }}
{{- end }}

{{/*
Compute and emit the configured gateway Pod ports.
*/}}
{{- define "ignition.gateway.containerPorts" -}}
  {{- $ports := dict -}}
  {{- $_ := set $ports "http" "8088" -}}
  {{- $_ := set $ports "https" "8043" -}}
  {{- $_ := set $ports "gan" "8060" -}}
  {{- if .Values.commissioning.ports }}
    {{- fail "ERROR: Port configuration has moved from commissioning.ports to gateway.ports in v0.0.30 of this Chart." }}
  {{- end }}
  {{- $ports = merge (.Values.gateway.ports | default dict) $ports -}}
  {{- range $portName, $portNumber := $ports }}
- name: {{ $portName }}
  containerPort: {{ $portNumber }}
  {{- end -}}
{{- end }}

{{/*
Compute and emit the configured gateway Service ports.
*/}}
{{- define "ignition.gateway.servicePorts" -}}
  {{- $context := index . 0 }}
  {{- $suffix := index . 1 }}
  {{- $serviceType := index . 2 }}
  {{- $gatewayPorts := $context.Values.gateway.ports }}
  {{- $baseLoadBalancerPorts := $context.Values.service.loadBalancerPorts | default dict }}
  {{- $loadBalancerPorts := (get $context.Values.service (empty $suffix | ternary "loadBalancerPorts" (printf "%sLoadBalancerPorts" $suffix))) | default dict }}
  {{- $loadBalancerPorts = merge $loadBalancerPorts $baseLoadBalancerPorts }}
  {{- $baseNodePorts := $context.Values.service.nodePorts | default dict }}
  {{- $nodePorts := (get $context.Values.service (empty $suffix | ternary "nodePorts" (printf "%sNodePorts" $suffix))) | default dict -}}
  {{- $nodePorts = merge $nodePorts $baseNodePorts }}
  {{- $baseCustomPorts := $context.Values.service.customPorts | default list }}
  {{- $customPorts := $baseCustomPorts }}
  {{- if not (empty $suffix) }}
  {{- $customPorts = concat $baseCustomPorts ((get $context.Values.service (printf "%sCustomPorts" $suffix)) | default list) -}}
  {{- end }}
  {{- if eq $serviceType "LoadBalancer" }}
  {{- $_ := required "Must specify at least one LoadBalancer port" (eq (len $loadBalancerPorts) 0 | ternary "" "noop") }}
  {{- end }}
  {{- if eq $serviceType "NodePort" }}
  {{- $_ := required "Must specify at least one NodePort port" (eq (len $nodePorts) 0 | ternary "" "noop") }}
  {{- end }}
  {{- if (gt (len $customPorts) 0) }}
  {{- toYaml $customPorts | nindent 0 }}
  {{- else if eq $serviceType "LoadBalancer" }}
  {{- range $portName, $portNumber := $loadBalancerPorts }}
- name: {{ $portName }}
  port: {{ $portNumber }}
  targetPort: {{ $portName }}
  {{- end }}
  {{- else if eq $serviceType "NodePort" }}
  {{- range $portName, $portNumber := $nodePorts }}
- name: {{ $portName }}
  port: {{ $portNumber }}
  targetPort: {{ $portName }}
  {{- end }}
  {{- else }}
  {{- range $portName, $portNumber := $gatewayPorts }}
- name: {{ $portName }}
  port: {{ $portNumber }}
  targetPort: {{ $portNumber }}
  {{- end }}
  {{- end -}}
{{- end }}

{{/*
Compute and emit the gateway pod ports for use in ConfigMap.
*/}}
{{- define "ignition.gateway.portEnvs" -}}
  {{- $ports := dict -}}
  {{- $_ := set $ports "http" "8088" -}}
  {{- $_ := set $ports "https" "8043" -}}
  {{- $_ := set $ports "gan" "8060" -}}
  {{- $mergePorts := merge (.Values.gateway.ports | default dict) $ports -}}
  {{- range $key, $value := $mergePorts }}
    {{- if has $key (keys $ports) }}
      {{- printf "\nGATEWAY_%s_PORT: %s" ($key | upper) ($value | quote) }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
Convenience method for emitting the environment variable name for a public address setting.
*/}}
{{- define "ignition.gateway.publicAddressEnvVarName" -}}
  {{- $suffix := index . 0 }}
  {{- $mode := index . 1 }}
  {{- print "GATEWAY_PUBLIC_" ($suffix | upper) }}
  {{- if not (empty $mode) }}
    {{- print "_" ($mode | upper) }}
  {{- end }}
{{- end }}

{{/*
Resolve, on a best-effort basis, an environment variable value in either list/map form from .Values.gateway.env
Typical use would be with 'coalesce' to find an existing value (or use a default fallback).
Returns the blank if the value is not found.
*/}}
{{- define "ignition.gateway.envValue" -}}
  {{- $context := index . 0 -}}
  {{- $searchValue := index . 1 -}}

  {{- if (kindIs "slice" $context.Values.gateway.env) -}}
    {{- range $env := $context.Values.gateway.env }}
      {{- $name := (get . "name") }} 
      {{- if (eq $name $searchValue) }}
        {{- get . "value" }}
      {{- end }}
    {{- end }}
  {{- else if (kindIs "map" $context.Values.gateway.env) }}
    {{- get $context.Values.gateway.env $searchValue }}
  {{- else if (kindIs "invalid" $context.Values.gateway.env) }}
    {{- "" }}
  {{- else }}
    {{- fail (printf "Unexpected type for gateway.env: %s" (kindOf $context.Values.gateway.env)) }}
  {{- end }}
{{- end }}

{{/*
Emit a resources block for the Ignition gateway and preconfigure containers
*/}}
{{- define "ignition.gateway.resources" -}}
  {{- if .Values.gateway.resourcesEnabled }}
  resources:
    {{- if .Values.gateway.resources }}
      {{- toYaml .Values.gateway.resources | nindent 4 }}
    {{- else }}
    limits:
      cpu: 1000m
      memory: 1536Mi
    requests:
      cpu: 1000m
      memory: 1536Mi
    {{- end }}
  {{- end }}
{{- end }}

{{/*
Compute and emit the gateway public address settings as environment variables.
*/}}
{{- define "ignition.gateway.publicAddressEnvs" -}}
  {{/* Context should be the root context */}}
  {{- $context := index . 0 -}}
  {{/* Mode should be either "map" or "array" */}}
  {{- $mode := index . 1 -}}

  {{/* Create an empty dictionary to collect env var mappings */}}
  {{- $envMap := dict -}}

  {{- /* Auto-apply if ingress+tls is enabled */ -}}
  {{- range $redundancyMode := ($context.Values.gateway.redundancy.enabled | ternary (list "primary" "backup") (list "")) }}
    {{- $hostFQDN := (include "ignition.ingress.hostName" (list $context $redundancyMode)) -}}
    {{- $customTLS := (include "ignition.ingress.customTLS" (list $context $redundancyMode)) -}}
    {{- /* Default/Auto Values, if ingress is enabled without custom TLS definition. */ -}}
    {{- if (and (not $customTLS) ($context.Values.ingress.enabled)) }}
      {{- $_ := set $envMap (include "ignition.gateway.publicAddressEnvVarName" (list "ADDRESS" $redundancyMode)) $hostFQDN }}
      {{- $_ := set $envMap (include "ignition.gateway.publicAddressEnvVarName" (list "HTTP_PORT" $redundancyMode)) 80 }}
      {{- $_ := set $envMap (include "ignition.gateway.publicAddressEnvVarName" (list "HTTPS_PORT" $redundancyMode)) 443 }}
    {{- end }}
    {{- /* Overrides based on the gateway.publicAddress explicit settings, if present */ -}}
    {{- $publicAddressKey := (empty $redundancyMode | ternary "publicAddress" ((print $redundancyMode "PublicAddress") | untitle)) }}
    {{- with (get $context.Values.gateway $publicAddressKey) -}}
      {{- if (not .autoDetect) }}
        {{- $_ := required (print "Missing " $redundancyMode " public address host value!") .host }}
        {{- $_ := set $envMap (include "ignition.gateway.publicAddressEnvVarName" (list "ADDRESS" $redundancyMode)) (.host | default $hostFQDN) }}
        {{- $_ := set $envMap (include "ignition.gateway.publicAddressEnvVarName" (list "HTTP_PORT" $redundancyMode)) (.http | default 80) }}
        {{- $_ := set $envMap (include "ignition.gateway.publicAddressEnvVarName" (list "HTTPS_PORT" $redundancyMode)) (.https | default 443) }}
      {{- else }}
        {{- $_ := unset $envMap (include "ignition.gateway.publicAddressEnvVarName" (list "ADDRESS" $redundancyMode)) }}
        {{- $_ := unset $envMap (include "ignition.gateway.publicAddressEnvVarName" (list "HTTP_PORT" $redundancyMode)) }}
        {{- $_ := unset $envMap (include "ignition.gateway.publicAddressEnvVarName" (list "HTTPS_PORT" $redundancyMode)) }}
      {{- end }}
    {{- end }}
  {{- end }}

  {{- if eq $mode "map" }}
    {{- range $key, $value := $envMap }}
      {{- printf "\n%s: %s" $key ($value | quote) }}
    {{- end }}
  {{- else if eq $mode "array" }}
    {{- range $key, $value := $envMap }}
      {{- printf "\n- name: %s" $key }}
      {{- printf "\n  value: %s" ($value | quote) }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
Render supplemental env var values for the gateway container.
*/}}
{{- define "ignition.gateway.env" -}}
  {{- if eq (kindOf .Values.gateway.env) "map" -}}
    {{- range $varName, $varValue := .Values.gateway.env }}
      {{- printf "\n- name: %s" $varName }}
      {{- printf "\n  value: %s" ($varValue | quote) }}
    {{- end }}
  {{- else -}}
    {{- with .Values.gateway.env }}
      {{- println -}}
      {{- . | toYaml }}
    {{- end }}
  {{- end -}}
{{- end -}}

{{/*
Render outgoing GAN connection definitions for use in ConfigMap.
*/}}
{{- define "ignition.gateway.ganOutgoingConnections" -}}
  {{- range $i, $connection := .Values.gateway.gan.outgoingConnections -}}
    {{- range $key, $value := $connection -}}
      {{- printf "\nGATEWAY_NETWORK_%v_%s: %s" $i ($key | upper) ((tpl (toString $value) $)| quote) }}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- define "ignition.gateway.ganRequireTwoWayAuth" -}}
  {{- $keyName := "GATEWAY_NETWORK_REQUIRETWOWAYAUTH" -}}
  {{- if eq false .Values.gateway.gan.requireTwoWayAuth -}}
    {{- printf "\n%s: %v" $keyName ("false" | quote) }}
  {{- else if (or .Values.gateway.gan.requireTwoWayAuth .Values.certManager.enabled) -}}
    {{- printf "\n%s: %v" $keyName ("true" | quote) }}
  {{- end -}}
{{- end }}

{{/*
Generate, if applicable, and emit the gateway admin password Secret resource name.
*/}}
{{- define "ignition.gateway.gatewayAdminSecret" -}}
  {{- if empty .Values.commissioning.auth.existingSecret }}
    {{- printf "%s-%s" (include "ignition.fullname" .) "gateway-admin-password" }}
  {{- else -}}
    {{- .Values.commissioning.auth.existingSecret -}}
  {{- end }}
{{- end -}}

{{/*
Emit the computed replicas count, based on either explicit values or redundancy config
*/}}
{{- define "ignition.gateway.replicas" -}}
  {{- $replicas := .Values.gateway.replicas | default 1 -}}
  {{ if .Values.gateway.redundancy.enabled -}}
    {{- $replicas = 2 -}}
  {{- end }}
  {{- printf "%v" $replicas }}
{{- end }}

{{/*
Render the GAN Issuer Name, using the override if applicable.
*/}}
{{- define "ignition.gateway.ganIssuerName" -}}
  {{- .Values.certManager.ganIssuer.nameOverride | default (printf "%s-%s" (include "ignition.fullname" .) "gan-issuer") }}
{{- end -}}

{{/*
Render the GAN Issuer Secret Name, using the custom spec or override if applicable.
*/}}
{{- define "ignition.gateway.ganIssuerSecret" -}}
{{- if .Values.certManager.ganIssuer.customSpec -}}
{{ .Values.certManager.ganIssuer.customSpec.secretName -}}
{{- else -}}
{{ .Values.certManager.ganIssuer.spec.secretNameOverride | default (include "ignition.gateway.ganIssuerName" .) -}}
{{- end -}}
{{- end -}}

{{/*
Render the TLS Issuer Name, using the override if applicable.
*/}}
{{- define "ignition.gateway.tlsIssuerName" -}}
  {{- .Values.certManager.tlsIssuer.nameOverride | default (printf "%s-%s" (include "ignition.fullname" .) "tls-issuer") }}
{{- end -}}

{{/*
Render the TLS Issuer Secret Name, using the custom spec or override if applicable.
*/}}
{{- define "ignition.gateway.tlsIssuerSecret" -}}
{{- if .Values.certManager.tlsIssuer.customSpec -}}
{{ .Values.certManager.tlsIssuer.customSpec.secretName -}}
{{- else -}}
{{ .Values.certManager.tlsIssuer.spec.secretNameOverride | default (include "ignition.gateway.tlsIssuerName" .) -}}
{{- end -}}
{{- end -}}

{{/*
Render the GAN Metro Keystore Secret Resource name.
*/}}
{{- define "ignition.gateway.ganKeystoreSecret" -}}
  {{- if empty .Values.gateway.gan.keystoreExistingSecret }}
    {{- printf "%s-%s" (include "ignition.fullname" .) "gan-metro-keystore" }}
  {{- else }}
    {{- .Values.gateway.gan.keystoreExistingSecret }}
  {{- end }}
{{- end -}}

{{/*
Render the GAN Certificate Name, using the override if applicable.
*/}}
{{- define "ignition.gateway.ganCertificateName" -}}
  {{- .Values.certManager.ganCertificate.nameOverride | default (printf "%s-%s" (include "ignition.fullname" .) "gan") }}
{{- end -}}

{{/*
Render the GAN Certificate Secret Name.  Precedence is an existing secret, custom spec secretName, the override, or computed name.
*/}}
{{- define "ignition.gateway.ganCertificateSecret" -}}
  {{- if .Values.gateway.gan.existingSecret -}}
    {{- .Values.certManager.gan.existingSecret -}}
  {{- else if .Values.certManager.ganCertificate.customSpec -}}
    {{- .Values.certManager.ganCertificate.customSpec.secretName -}}
  {{- else -}}
    {{- .Values.certManager.ganCertificate.spec.secretNameOverride | default (include "ignition.gateway.ganCertificateName" .) -}}
  {{- end -}}
{{- end -}}

{{/*
Render the TLS Certificate Name, using the override if applicable.
*/}}
{{- define "ignition.gateway.tlsCertificateName" -}}
  {{- .Values.certManager.tlsCertificate.nameOverride | default (printf "%s-%s" (include "ignition.fullname" .) "tls") }}
{{- end -}}

{{/*
Render the TLS Certificate Secret Name.  Precedence is an existing secret, custom spec secretName, the override, or computed name.
*/}}
{{- define "ignition.gateway.tlsCertificateSecret" -}}
  {{- if .Values.gateway.tls.existingSecret -}}
    {{- .Values.gateway.tls.existingSecret -}}
  {{- else if (and .Values.certManager.enabled .Values.certManager.tlsCertificate.customSpec) -}}
    {{- .Values.certManager.tlsCertificate.customSpec.secretName -}}
  {{- else if (.Values.certManager.enabled) -}}
    {{- .Values.certManager.tlsCertificate.spec.secretNameOverride | default (include "ignition.gateway.tlsCertificateName" .) -}}
  {{- else -}}
    {{- printf "%s-%s" (include "ignition.fullname" .) "tls" -}}
  {{- end -}}
{{- end -}}

{{/*
Render the TLS Keystore Secret Resource name.
*/}}
{{- define "ignition.gateway.tlsKeystoreSecret" -}}
  {{- printf "%s-%s" (include "ignition.fullname" .) "tls-keystore" }}
{{- end -}}

{{/*
Render an Ingress Hostname based on redundancy configuration
*/}}
{{- define "ignition.ingress.hostName" -}}
  {{- $context := index . 0 }}
  {{- $redundancyMode := index . 1 }}

  {{- $prefix := (printf "%s-%s" (include "ignition.fullname" $context) $redundancyMode) }}
  {{- if empty $redundancyMode }}
    {{- $prefix = (include "ignition.fullname" $context) }}
  {{- end }}
  {{- $baseHost := (get $context.Values.ingress (empty $redundancyMode | ternary "hostOverride" (printf "%sHostOverride" $redundancyMode))) }}
  {{- $host := (empty $baseHost | ternary (get $context.Values.ingress "hostOverride") $baseHost) }}
  {{- $host = $host | default (printf "%s.%s" $prefix $context.Values.ingress.domainSuffix) }}
  {{- printf "%s" $host }}
{{- end }}

{{/*
Render an array of Ingress Hostnames, including pod-indexed hostnames where applicable
*/}}
{{- define "ignition.ingress.hostNames" -}}
{{- $baseHost := (include "ignition.ingress.hostName" (list . "")) -}}
- {{ $baseHost | quote }}
  {{- if .Values.gateway.redundancy.enabled }}
    {{- range $redundancyMode := (list "primary" "backup") }}
      {{- $host := (include "ignition.ingress.hostName" (list $ $redundancyMode)) }}
      {{- if ne $host $baseHost }}
- {{ $host | quote }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- range $i := until ((include "ignition.ingress.podIndexedHostNameCount" .) | int) }}
- {{ (include "ignition.ingress.podIndexedHostName" (list $ $i)) | quote }}
  {{- end }}
{{- end }}

{{/*
Renders the count of pod-indexed ingress rules and/or services
*/}}
{{- define "ignition.podIndexedCount" -}}
  {{- $redundancyDisabled := (not .Values.gateway.redundancy.enabled) }}
  {{- $replicaCount := (include "ignition.gateway.replicas" .) | int }}
  {{- $replicasGreaterThanOne := (gt $replicaCount 1) }}
  {{- if (and $redundancyDisabled $replicasGreaterThanOne) -}}
    {{- $_ := required "Must specify service.podIndexedServices.create=true to use pod-indexed Ingress Rules"
      ((and 
        .Values.ingress.podIndexedIngressRules.create 
        (not .Values.service.podIndexedServices.create)
        ) | ternary "" "true")
    }}
    {{- printf "%d" $replicaCount }}
  {{- else }}
    {{- printf "%d" 0 }}
  {{- end }}
{{- end }}

{{/*
Renders the count of pod-indexed host names that should be generated
Will be 0 when feature should be disabled
*/}}
{{- define "ignition.ingress.podIndexedHostNameCount" -}}
  {{- if .Values.ingress.podIndexedIngressRules.create -}}
    {{- include "ignition.podIndexedCount" . }}
  {{- else }}
    {{- printf "%d" 0 }}
  {{- end }}
{{- end }}

{{/*
Renders the count of pod-indexed services that should be generated
Will be 0 when feature should be disabled
*/}}
{{- define "ignition.service.podIndexedServiceCount" -}}
  {{- if .Values.service.podIndexedServices.create -}}
    {{- include "ignition.podIndexedCount" . }}
  {{- else }}
    {{- printf "%d" 0 }}
  {{- end }}
{{- end }}

{{/*
Renders the service name for the Ignition Gateway
*/}}
{{- define "ignition.service.serviceName" -}}
  {{- $context := .context }}
  {{- $suffix := .suffix }}

  {{- $serviceNameBase := include "ignition.fullname" $context -}}
  {{- $serviceName := empty $suffix | ternary $serviceNameBase (printf "%s-%s" $serviceNameBase $suffix) -}}   
  {{- printf "%s" $serviceName }}
{{- end }}

{{/*
Render an Ingress Hostname, but with an injected suffix on the first segment
*/}}
{{- define "ignition.ingress.podIndexedHostName" -}}
  {{- $context := index . 0 }}
  {{- $i := index . 1 }}

  {{- $hostName := include "ignition.ingress.hostName" (list $context "") }}
  {{- $suffix := printf "%s%d" $context.Values.ingress.podIndexedIngressRules.suffixDelimiter $i }}
  {{- $segments := splitList "." $hostName }}
  {{- if gt (len $segments) 1 }}
    {{- $hostName = append (list (printf "%s%s" (index $segments 0) $suffix)) (slice $segments 1 | join ".") | join "." }}
  {{- else }}
    {{- $hostName = (printf "%s%s" $hostName $suffix) }}
  {{- end }}

  {{- printf "%s" $hostName }}
{{- end }}

{{/*
Emit custom Ingress rules, if defined.
*/}}
{{- define "ignition.ingress.customRules" -}}
  {{- $context := index . 0 -}}
  {{- $redundancyMode := index . 1 -}}

  {{- $customRules := get $context.Values.ingress "customRules" -}}
  {{- $redundancyCustomRules := get $context.Values.ingress ((print $redundancyMode "CustomRules") | untitle) -}}
  {{- $output := coalesce $redundancyCustomRules $customRules -}}

  {{- with $output -}}
  {{- . | toYaml }}
  {{- end }}
{{- end }}

{{/*
Emit extra Ingress rules, if defined.
*/}}
{{- define "ignition.ingress.extraRules" -}}
  {{- $context := index . 0 -}}
  {{- $redundancyMode := index . 1 -}}

  {{- $extraRules := get $context.Values.ingress "extraRules" -}}
  {{- $redundancyExtraRules := get $context.Values.ingress ((print $redundancyMode "ExtraRules") | untitle) -}}
  {{- $output := coalesce $redundancyExtraRules $extraRules -}}

  {{- with $output -}}
  {{- . | toYaml }}
  {{- end }}
{{- end }}

{{/*
Compute and emit the default value for the useProxyForwardedHeader setting, typically true with Ingress enabled.
*/}}
{{- define "ignition.ingress.useProxyForwardedHeader" }}
  {{- .Values.ingress.enabled | ternary "true" "false" }}
{{- end }}

{{/*
Emit custom Ingress TLS settings, if defined.
*/}}
{{- define "ignition.ingress.customTLS" -}}
  {{- $context := index . 0 -}}
  {{- $redundancyMode := index . 1 -}}

  {{- $customTLS := get $context.Values.ingress "customTLS" -}}
  {{- $redundancyCustomTLS := get $context.Values.ingress ((print $redundancyMode "CustomTLS") | untitle) -}}
  {{- $output := coalesce $redundancyCustomTLS $customTLS -}}

  {{- with $output -}}
  {{- . | toYaml }}
  {{- end }}
{{- end }}

{{/*
Helper template to reject based on unsupported leased licensing values configuration
*/}}
{{- define "ignition.gateway.licensing.leasedActivation.configCheck" -}}
  {{- $licensing := .Values.gateway.licensing -}}
  {{- $failMessage := "" -}}

  {{- $secretName := dig "leasedActivation" "secretName" nil $licensing }}
  {{- $primarySecretName := dig "primaryLeasedActivation" "secretName" nil $licensing }}
  {{- $backupSecretName := dig "backupLeasedActivation" "secretName" nil $licensing }}

  {{- $shouldCheck := gt (add
    (len (dig "leasedActivation" dict $licensing))
    (len (dig "primaryLeasedActivation" dict $licensing))
    (len (dig "backupLeasedActivation" dict $licensing))
  ) 0 -}}

  {{- /* Check for redundancy secret names */ -}}
  {{- if and .Values.gateway.redundancy.enabled $shouldCheck -}}
    {{- if and (eq nil $secretName) (or (eq nil $primarySecretName) (eq nil $backupSecretName)) }}
      {{- $failMessage = "Must supply primary/backup or shared licensing Secret name" }}
    {{- end }}
  {{- end }}

  {{- /* Check for standalone secret name */ -}}
  {{- if and (not .Values.gateway.redundancy.enabled) $shouldCheck -}}
    {{- if (eq nil $secretName) }}
      {{- $failMessage = "Must supply licensing Secret name" }}
    {{- end }}
  {{- end }}

  {{- /* Throw failure if message is defined */ -}}
  {{- if ne $failMessage "" -}}
    {{- fail $failMessage }}
  {{- end }}
{{- end }}

{{/*
Returns "true" if leased activation licensing should use a redundancy split configuration
*/}}
{{- define "ignition.gateway.licensing.leasedActivation.useRedundancySplit" -}}
  {{- $licensing := .Values.gateway.licensing -}}
  {{- $shouldRender := gt (add
    (len (dig "leasedActivation" dict $licensing))
    (len (dig "primaryLeasedActivation" dict $licensing))
    (len (dig "backupLeasedActivation" dict $licensing))
  ) 0 -}}

  {{- printf "%t" (and $shouldRender .Values.gateway.redundancy.enabled) }}
{{- end }}

{{/*
Returns "true" if leased activation sessions should be terminated during graceful shutdown
*/}}
{{- define "ignition.gateway.licensing.leasedActivation.terminateSessionOnShutdown" -}}
  {{- $licensing := .Values.gateway.licensing -}}
  {{- $terminate := dig "leasedActivation" "terminateSessionOnShutdown" false $licensing -}}
  {{- printf "%t" $terminate }}
{{- end }}

{{/*
Helper template to render projected secret sources for leased licensing configuration, use with indent
*/}}
{{- define "ignition.gateway.licensing.leasedActivation.projectedSecretSources" -}}
  {{- $licensing := .Values.gateway.licensing -}}

  {{- $secretName := dig "leasedActivation" "secretName" nil $licensing }}
  {{- $primarySecretName := dig "primaryLeasedActivation" "secretName" nil $licensing }}
  {{- $backupSecretName := dig "backupLeasedActivation" "secretName" nil $licensing }}
  {{- $licenseKeyKey := dig "leasedActivation" "licenseKeyKey" nil $licensing }}
  {{- $primaryLicenseKeyKey := dig "primaryLeasedActivation" "licenseKeyKey" nil $licensing }}
  {{- $backupLicenseKeyKey := dig "backupLeasedActivation" "licenseKeyKey" nil $licensing }}
  {{- $activationTokenKey := dig "leasedActivation" "activationTokenKey" nil $licensing }}
  {{- $primaryActivationTokenKey := dig "primaryLeasedActivation" "activationTokenKey" nil $licensing }}
  {{- $backupActivationTokenKey := dig "backupLeasedActivation" "activationTokenKey" nil $licensing }}

  {{- $shouldRender := gt (add
    (len (dig "leasedActivation" dict $licensing))
    (len (dig "primaryLeasedActivation" dict $licensing))
    (len (dig "backupLeasedActivation" dict $licensing))
  ) 0 -}}

  {{- $useRedundancySplit := eq "true" (include "ignition.gateway.licensing.leasedActivation.useRedundancySplit" .) -}}

  {{- if $useRedundancySplit -}}
    {{- $primarySecretName = coalesce $primarySecretName $secretName -}}
    {{- $backupSecretName = coalesce $backupSecretName $secretName -}}
    {{- $primaryLicenseKeyKey = coalesce $primaryLicenseKeyKey $licenseKeyKey "ignition-license-key" -}}
    {{- $backupLicenseKeyKey = coalesce $backupLicenseKeyKey $licenseKeyKey "ignition-license-key" -}}
    {{- $primaryActivationTokenKey = coalesce $primaryActivationTokenKey $activationTokenKey "ignition-activation-token" -}}
    {{- $backupActivationTokenKey = coalesce $backupActivationTokenKey $activationTokenKey "ignition-activation-token" -}}
- secret:
    name: {{ $primarySecretName }}
    items:
    - key: {{ $primaryLicenseKeyKey }}
      path: primary-ignition-license-key
    - key: {{ $primaryActivationTokenKey }}
      path: primary-ignition-activation-token
    {{- if not (eq $primarySecretName $backupSecretName) }}
- secret:
    name: {{ $backupSecretName }}
    items:
    {{- end }}
    - key: {{ $backupLicenseKeyKey }}
      path: backup-ignition-license-key
    - key: {{ $backupActivationTokenKey }}
      path: backup-ignition-activation-token
  {{- end }}

  {{- if and (not $useRedundancySplit) $shouldRender -}}
- secret:
    name: {{ $secretName }}
    items:
    - key: {{ $licenseKeyKey | default "ignition-license-key" }}
      path: ignition-license-key
    - key: {{ $activationTokenKey | default "ignition-activation-token" }}
      path: ignition-activation-token
  {{- end }}
{{- end }}

{{/*
Helper template to inject default key names for leased activation licensing.
*/}}
{{- define "ignition.gateway.licensing.setDefaults" -}}
  {{- if not (hasKey . "licenseKeyKey") -}}
    {{- $_ := set . "licenseKeyKey" "ignition-license-key" -}}
  {{- end -}}
  {{- if not (hasKey . "activationTokenKey") -}}
    {{- $_ := set . "activationTokenKey" "ignition-activation-token" -}}
  {{- end -}}
{{- end }}

{{/*
Render an invocation of the prepare-redundancy.sh script, adding a flag for redundant licensing prep if applicable
*/}}
{{- define "ignition.gateway.redundancy.prepareSh" -}}
  {{- $args := list -}}
  {{- if (and .Values.gateway.redundancy .Values.gateway.redundancy.enabled) -}}
    {{- $args = append $args "/config/scripts/prepare-redundancy.sh" -}}

    {{/* Required Args */}}
    {{- $args = append $args "-g" -}}
    {{- $args = append $args ((print (include "ignition.fullname" .) "-gateway-0." (include "ignition.fullname" .)) | quote) -}}

    {{/* Optional args */}}
    {{- if (eq "true" (include "ignition.gateway.licensing.leasedActivation.useRedundancySplit" .)) -}}
      {{- $args = append $args "-l" -}}
    {{- end -}}
    {{- if eq "false" (coalesce (include "ignition.gateway.envValue" (list . "GATEWAY_NETWORK_REQUIRESSL")) "true") -}}
      {{- $args = append $args "-k" -}}
    {{- end -}}

    {{- $args = append $args "-v" -}}

    {{- with $args -}}
      {{- join " " . }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
Render a pod-level security context block
*/}}
{{- define "ignition.security.podSecurityContext" }}
  {{- if not (eq . nil) }}
    {{- printf "securityContext:" }}
    {{- if . -}}
      {{- toYaml . | nindent 2}}
    {{- else }}
  runAsUser: 2003
  runAsGroup: 2003
  fsGroup: 2003
  runAsNonRoot: true
    {{- end }}
  {{- end }}
{{- end }}

{{/*
Render a container-level security context block
*/}}
{{- define "ignition.security.containerSecurityContext" }}
  {{- if not (eq . nil) }}
    {{- printf "securityContext:" }}
    {{- if . -}}
      {{- toYaml . | nindent 2}}
    {{- else }}
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  seccompProfile:
    type: RuntimeDefault
    {{- end }}
  {{- end }}
{{- end }}

{{- define "ignition.renderCommaDelimitedArray" -}}
  {{- $array := . }}
  {{- $vals := list }}
  {{- range $array }}
    {{- $vals = append $vals (trim .) }}
  {{- end }}
  {{- printf "%s" (join "," $vals) }}
{{- end }}

{{/*
Accept a dictionary with `content` and `context` keys, and render the content using the context.
Test for if the content is a string and render accordingly.
Emit nothing if `.content` is null.
*/}}
{{- define "ignition.rinseThroughTpl" -}}
  {{- $context := .context }}
  {{- $content := .content }}
  {{- if not (eq $content nil) }}
    {{- $content := (typeOf $content | eq "string" | ternary $content (toYaml $content)) }}
    {{- (tpl $content $context) }}
  {{- end }}
{{- end }}
