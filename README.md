# Ignition Helm Chart

This repository contains the [Ignition Helm Chart](./ignition/) for deploying Ignition by Inductive Automation on Kubernetes.

For initial usage information, consult the chart [README](./ignition/README.md).  For more in-depth documentation, visit https://charts.ia.io.

## Verifying Chart Provenance and Signature

We sign each release of the Helm chart with a PGP keypair from "IA Helm Charts <charts@ia.io>".  You can use the public key to verify the authenticity of the chart .tgz file using the steps below:

1. Download the [public key](publickey.gpg.asc) and inspect:

```bash
curl -fsSL -O https://github.com/inductiveautomation/ignition-helm-chart/raw/main/publickey.gpg.asc
gpg --show-keys publickey.gpg.asc
```

The key should have fingerprint: `7D09D98C884BAE9248186059EFF55DC769C5C70D`

2. Import the public key and export your current set of public keys to a keyring file (used by Helm):

```bash
# Import the public key
gpg --import publickey.gpg.asc
# Export to public keys to legacy keyring format used by Helm CLI
gpg --export > ~/.gnupg/pubring.gpg
```

3. Verify the downloaded chart:

```bash
$ helm repo add inductiveautomation https://charts.ia.io
$ helm pull inductiveautomation/ignition --prov
$ helm verify ignition-*.tgz
Signed by: IA Helm Charts <charts@ia.io>
Using Key With Fingerprint: 7D09D98C884BAE9248186059EFF55DC769C5C70D
Chart Hash Verified: sha256:xxxxxxxxx
```
