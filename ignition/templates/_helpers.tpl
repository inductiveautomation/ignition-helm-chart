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
Returns "true" if .Values.gateway.maxRAMPercentage should be used
*/}}
{{- define "ignition.gateway.useMaxRAMPercentage" -}}
  {{- $maxRAMValueValid := (gt (.Values.gateway.maxRAMPercentage | int) 0) -}}
  {{- $resourcedEnabled := .Values.gateway.resourcesEnabled -}}
  {{/* Bring the computed resources into an object, defaulting to an empty dictionary */}}
  {{- $resources := fromYaml (include "ignition.gateway.resources" .) | default dict -}}
  {{/* Check if resources.limits.memory is set */}}
  {{- $resourcesMemoryLimitsExists := not (empty (dig "resources" "limits" "memory" "" $resources)) -}}
  {{- printf "%t" (and $maxRAMValueValid $resourcedEnabled $resourcesMemoryLimitsExists) }}
{{- end }}

{{/*
Emit the array elements for Ignition JVM args.
*/}}
{{- define "ignition.gateway.jvmArgs" -}}
  {{- /* Default JVM Args */ -}}
  {{- $jvmArgs := list }}
  {{- if eq "true" (include "ignition.gateway.useMaxRAMPercentage" .) -}}
    {{- $maxRAMPercentage := (.Values.gateway.maxRAMPercentage | default 50 | int) -}}
    {{- $initialRAMPercentage := (.Values.gateway.initialRAMPercentage | default $maxRAMPercentage) -}}
    {{- $jvmArgs = append $jvmArgs (printf "%s=%v" "-XX:InitialRAMPercentage" $initialRAMPercentage) -}}
    {{- $jvmArgs = append $jvmArgs (printf "%s=%v" "-XX:MaxRAMPercentage" $maxRAMPercentage) -}}
    {{- with .Values.gateway.maxDirectMemorySize }}
    {{- $jvmArgs = append $jvmArgs (printf "%s=%v" "-XX:MaxDirectMemorySize" .) -}}
    {{- end }}
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
{{- define "ignition.gateway.licensing.redundancyPrepareSh" -}}
  {{- $args := list -}}
  {{- if (and .Values.gateway.redundancy .Values.gateway.redundancy.enabled) -}}
    {{- $args = append $args "/config/scripts/prepare-redundancy.sh" -}}

    {{/* Required Args */}}
    {{- $args = append $args "-g" -}}
    {{- $args = append $args ((print (include "ignition.fullname" .) "-gateway-0." (include "ignition.fullname" .)) | quote) -}}

    {{/* Optional args */}}
    {{- if (and (hasKey .Values.gateway.licensing "primaryLeasedActivation") (hasKey .Values.gateway.licensing "backupLeasedActivation")) -}}
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
