# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Fixed an issue where `podLabels` were incorrectly applied to StatefulSet metadata instead of pod metadata.

### Changed

- Bumped _appVersion_ for Ignition to 8.3.3.
- Modified the redundant health check script to accept some additional states to facilitate better automated upgrades.

## [0.2.0] - 2025-09-15

⚠️ **WARNING:** Possible breaking changes related to Ingress and certificate generation.  Please apply extra consideration to these areas while testing upgrades to this version of the chart.

### Added

- Added `commissioning.acceptModuleLicenses` and `commissioning.acceptModuleCertificates` arrays for auto-acceptance of third-party module EULA and certificates, new with Ignition 8.3.0.
- Added `gateway.deploymentMode` to allow specifying Ignition deployment mode without needing to supply the raw JVM arg directly.
- Added `gateway.dataVolumeUseEmptyDir` to allow using an ephemeral emptyDir volume for the Ignition data volume instead of a PVC.  The size limit for the ephemeral volume will be applied from `gateway.dataVolumeStorageSize`.

### Fixed

- Removed a warning that emitted from creation of cert-manager certificates regarding private key rotation policy.  Set `privateKey.rotationPolicy` to `Always` which is the new default and recommended setting.

### Changed

- Changes to default `certManager.tlsCertificate` TLS certificate generation to use `ingress.hostName` in default spec.  Additionally, the common name is now included in the SAN list.
- Redundant configurations now use a single `Ingress` resource with individual rules for the primary/backup routes.  Role-specific variants for `ingress.extraRules`, `ingress.customTLS`, and `ingress.annotations` are no longer applicable and will be ignored.
- Bumped _appVersion_ for Ignition to 8.3.0.
- Modified various file paths for Ignition 8.3.0 compatibility.
- Refined gateway network and webserver TLS certificate prep scripts for 8.3.0 compatibility.

## [0.1.0] - 2025-09-07

### Added

- Added capability for setting up redundancy over unencrypted port `8088/tcp` for testing purposes.  Setting `gateway.env.GATEWAY_NETWORK_REQUIRESSL=false` along with `gateway.redundancy.enabled=true` will configure the redundancy settings accordingly.

### Fixed

- Fixed use of `gateway.gan.whitelist`, which was not being rendered in the base config map.

## [0.0.37] - 2025-07-11

### Changed

- `extraObjects` is now rendered through a new helper template that better standardizes rendering of arbitrary content.  There should be no changes to existing usages, but you can now also supply an object to each array item instead of only a multi-line string.
- `affinity` will now render template directives, allowing for more dynamic affinity rules to be declared.

### Fixed

- Fixed an issue where `podLabels` were not applied to the Ignition pod.
- Fixed an issue where the entrypoint shim might exit non-zero if the external modules directory did not exist.  In this scenario, the specified directory is now created.

## [0.0.36] - 2025-06-10

### Changed

- Bumped _appVersion_ for Ignition to 8.1.48.

### Fixed

- Fixed an issue where NOTES.txt was not rendering the admin password kubectl command correctly when custom secret names were being used.
- Fixed an issue where pod-indexed Ingress rules were not being suffixed when `ingress.hostOverride` was not a FQDN.

## [0.0.35] - 2025-04-23

### Added

- Added functional test for verifying basic Ignition Gateway startup via `helm test`.

### Changed

- Bumped minimum Kubernetes version to 1.29.0 to align with SidecarContainers feature support.

### Fixed

- Fixed an issue where pod-indexed Ingress rules were not being added to the TLS hosts when `ingress.tls.enabled=true`.

## [0.0.34] - 2025-04-16

### Fixed

- Fixed an issue where an incorrect secret name (for retrieving initial gateway admin password) could be emitted in NOTES.

## [0.0.33] - 2025-04-14

### Fixed

- Fixed an issue where `service.podIndexedServices` couldn't be enabled independently of pod-indexed ingress rule creation.
- Corrected changelog entry for 0.0.32 referencing `ingress.podIndexedIngressRules` values.

## [0.0.32] - 2025-04-14

### Added

- Added new guidance in NOTES.txt for retrieving initial gateway admin password on initial install.
- Added new guidance in NOTES.txt with URLs for accessing the Ignition Gateway[s].  Unified ingress hostnames via new helper template in chart.
- Added `service.podIndexedServices` and `ingress.podIndexedIngressRules` to allow for creation of individual services and ingress rules for each Ignition Gateway replica.  See the values.yaml defaults file for more information.

## [0.0.30] - 2025-04-11

### Added

- Added `ingress.extraRules` to allow for adding Ingress rules beyond the auto-generated base rules.
- Added `gateway.extraSpec` to allow for additional ad-hoc gateway container spec injection.
- Added `gateway.extraContainers` to define additional containers to run alongside the Ignition pod.
- Added `podExtraSpec` to allow for additional ad-hoc pod spec injection.

### Changed

- Bumped _appVersion_ for Ignition to 8.1.47.
- Public Address runtime args now supplied to Ignition by default when redundancy is disabled but ingress is enabled.
- Moved `commissioning.ports` to `gateway.ports` for clarity.  Upgrade will proactively error if you're currently using `commissioning.ports`.

### Fixed

- Adjusted minimum Chart `kubeVersion` to allow for compatibility with EKS cluster version identifiers.
- Fixed reference to existing TLS secret from `gateway.tls.existingSecret` for gateway `web-tls` secret.
- Prevented overlapping GAN/TLS cert rotation jobs from being spawned from CronJob.
- Fixed an issue where GAN/TLS cert rotation jobs were not being scheduled to same node as hosting pod, resulting in jobs being stuck in scheduling due to RWO PVC constraints.

## [0.0.29] - 2025-02-19

### Fixed

- Fixed an issue where using custom keys for `gateway.licensing.leasedActivation` license and activation tokens would not properly map to the env var file targets within the Ignition pod.

## [0.0.28] - 2025-02-19

### Added

- Added required K8s version of >=1.28 to Chart definition.
- Added `gateway.preconfigure.extraSpec` to allow for additional ad-hoc preconfigure container spec config.

### Changed

- Modified default for `ingress.tls.enabled` to be `false` to prevent dangling secret from blocking ingress config on certain ingress controllers in situations where TLS is not being used.
- Percentage-based JVM Heap memory allocation (`gateway.maxRAMPercentage`) is now only applied if resources are enabled and a memory limit is applied (which is the default).  When `gateway.resourcesEnabled=false`, Ignition will use its own default JVM heap settings, typically 256Mi initial and 1Gi max.  This will prevent Ignition from attempting to consume too much memory on the host if limits are not explicitly set.

### Fixed

- Fixed an issue where `image.pullPolicy` was not being applied to the pod containers.

## [0.0.27] - 2025-02-05

### Added

- Added option to set `commissioning.auth.adminUsername` to a blank value to prevent driving of gateway auth.  Default behavior of generating a random `Secret` for gateway admin password remains.

### Fixed

- Fixed an issue where the TLS Certificate (created when `certManager.enabled=true`) was referencing an incorrect TLS issuer by default.
- Fixed an issue where the `gateway.gan.keystoreExistingSecret`, if explicitly defined, was not being referenced within the `Certificate` resource generated with cert-manager integration enabled.

### Changed

- The gateway network keystore passphrase `Secret` is no longer created if cert-manager integration is not enabled.  This is used by the `Certificate` resource as the PKCS12 passphrase.
- The `https` named port will now be used in `Ingress` if `gateway.tls.enabled=true`.  If this behavior is not desirable, use `ingress.customRules` to override.
- The default name for TLS resources (`Secret` (2), `Certificate`) related to Ignition web server TLS are now `*-tls-*` instead of `*-web-*` to better align with default names generated by cert-manager annotations (which default to `<ingress-name>-tls`).  This allows easier "sharing" of the TLS secret should you decide to enable end-to-end TLS via `gateway.tls.enabled=true`.

## [0.0.26] - 2025-01-23

### Added

- Added sourcing of `data_clean` folder, if present, during data volume seeding for compatibility with Cloud Edition container image.
- Added `gateway.systemNameUseIndexed` (bool) to allow for enforcing use of pod suffix on gateway system name.
- Added `service.customPorts` to allow for full control of service port definitions; using this overrides any previous automatic port definitions.
- Added `service.nodePorts` to allow for defining NodePort values for service ports, similar to `service.loadBalancerPorts`.
- Bumped _appVersion_ for Ignition to 8.1.45.

### Fixed

- Fixed an issue where list (versus map) usage of `gateway.env` values would cause an error.
- Resources from `gateway.resources` (when enabled) are now applied to both gateway and preconfigure containers.
- Fixed an issue where explicitly setting `gateway.gan.requireTwoWayAuth` to `false` was not being properly reflected in the resultant configmap environment variable.
- Omit default driving of StatefulSet `updateStrategy` unless `gateway.updateStrategy` is explicitly set.  This fixes a constant out-of-sync issue in ArgoCD where `maxUnavailable` was being filtered from the applied spec.
- Fixed an issue where `ingress.hostOverride` wasn't coalescing with the redundancy-specific overrides.

### Changed

- Added optional rendering of Helm templates within `gateway.gan.outgoingConnections`.
- Pod index suffices will be applied to the gateway system name even when `gateway.systemNameOverride` is used.
- With cert-manager enabled but `gateway.tls.enabled=false`, the TLS Issuer and associated Certificate will no longer be created.

## [0.0.25] - 2024-11-22

### Added

- Added `image.entrypoint` to facilitate usage of custom image entrypoint shims to launch Ignition.
- Bumped _appVersion_ for Ignition to 8.1.44.

## [0.0.24] - 2024-10-15

### Added

- Added `gateway.dataVolumeStorageClass` to allow customizing storage class for Ignition data volume.

## [0.0.23] - 2024-10-08

### Added

- Added `ingress.hostOverride` awareness of `*` to allow for omitting the `host` field.  Removed `ingress.omitHost` setting.

## [0.0.22] - 2024-10-08

### Added

- Added `ingress.omitHost` to allow for disabling the `host` field in Ingress resource.
- Added new `initContainers` section for defining additional init container specs.

### Fixed

- Fixed type mismatch error in max RAM percentage value setting.

### Changed

- Grouped `imagePullSecrets` under `image.pullSecrets` alongside other related image settings.
- Reordered some of the top-level values entries.
- Defaulted initial RAM percentage to match max.
- Restructured preconfigure init container, moved `preconfigureCmds` to `preconfigure.additionalCmds`.  Added `preconfigure.seedDataVolume` boolean and global `preconfigure.enabled` for flexibility.
- Modified default `commissioning.edition` to be unspecified rather than defaulting to "standard".

## [0.0.21] - 2024-09-11

### Changed

- Some additional refinements to default `podAntiAffinity` selector.

## [0.0.20] - 2024-09-11

### Fixed

- Small fix for `podAntiAffinity` label selector.

## [0.0.18] - 2024-09-11

### Added 

- Added `service.extraSpec` for additional ad-hoc service spec config.

### Changed

- Moved `serviceAnnotations` to `service.annotations` for better grouping.
- Reduced default resources allocation to 1 CPU and 1536Mi RAM, down from 2 cpu and 2048Mi RAM.

## [0.0.17] - 2024-09-10

### Added

- Added support for primary/backup annotation customization on Ingress resources.

### Changed

- Moved `auth` from `gateway` to `commissioning` for better alignment.
- Removed `gateway.redundancy` primary/backup public addr settings, instead locating the alternative key guidance under the main `gateway.publicAddress` key comments for better alignment.
- Reorganized leased activation settings for redundancy split configurations.
- Reorganized service annotations for redundancy split configurations.
- Reorganized load balancer service port settings for redundancy split configurations.

## [0.0.16] - 2024-08-30

### Added

- Added support for external Ignition modules via separate PVC and entrypoint shim logic.

### Changed

- Enabled default resource requests/limits and adjusted initial default maxRamPercentage to 75

## [0.0.15] - 2024-08-30

### Changed

- Bundled EXAMPLES into README for easier retrieval via Helm CLI.

## [0.0.14] - 2024-08-30

### Fixed

- Apply quoting in cert rotation CronJobs.

## [0.0.13] - 2024-08-30

### Fixed

- Fix TLS certificate rotation CronJob schedule to draw from values setting.

## [0.0.12] - 2024-08-30

### Added

- Added EXAMPLES docs.

### Changed

- Minor fix to gateway arg collection.

## [0.0.11] - 2024-08-30

### Added

- Added CronJob resources for rotating PKCS12 keystores from Secret objects into the gateway container on a schedule.
- Added ConfigMap checksum to Ignition podspec to force update on update of scripts/files/envVars in the chart

### Changed

- Made redundancy preparation more idempotent for role and GAN host target.
- Enforced GAN two-way auth (when not explicitly defined) only when cert-manager integration is enabled.
- Some minor refinements to redundant-health-check.sh script, including readiness during manual commissioning.

## [0.0.10] - 2024-08-27

### Added

Initial draft.
