# Ignition Helm Chart

This chart installs an Ignition Gateway (either as a redundant pair, or a set of independent replicas) as a Helm "release".

## Usage

The default values will deploy a single Ignition Gateway w/ Ingress enabled:

```bash
# Add the helm repository
helm repo add inductiveautomation https://charts.ia.io

# Install a release named "ignition" from the `inductiveautomation/ignition` chart
# NOTE: if you're using a local version of the chart, simply invoke the command
#       from the same directory and replace `inductiveautomation/ignition` with `.`
helm upgrade --install ignition inductiveautomation/ignition
```

## Examples

This section shows some examples of how to use this chart to deploy Ignition in varying production scenarios.  Read through the [Overview](#overview) and [Single Gateway Deployment](#single-gateway-deployment) example to run through an example installation and removal of the chart.  Other examples later in the document will show the `values.yaml` content, but assume the installation commands to be understood (i.e. `helm upgrade --install ...`).

### Prerequisites

#### cert-manager

Many of the examples will leverage [cert-manager](https://cert-manager.io) integration offered by the chart via `certManager.enabled=true` value setting.  Consult [cert-manager installation](https://cert-manager.io/docs/installation/) documentation for more information about how to install and properly configure it for production use.

For these examples against a development cluster, you can install via the [cert-manager Helm Chart](https://cert-manager.io/docs/installation/helm/).

The default integrations also target a global self-signed `ClusterIssuer` (this can be customized, of course).  You can create this yourself by applying the following manifest:

```bash
# Example using Linux/macOS/WSL2 shell
kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
```

#### Ingress Controller

Additionally, some examples also assume that you have configured an Ingress Controller for your cluster.  This might be something like Traefik, NGINX Ingress Controller, or maybe of the other options in the K8s ecosystem.  The examples in the demo will use [Traefik annotations](https://doc.traefik.io/traefik/routing/providers/kubernetes-ingress/#annotations), but they can be easily adjusted to match your Ingress configuration.

### Overview

There is a lot of reading out there on Helm; this overview isn't meant to replace that wealth of information.  Regardless, below are some high-level points that might help provide a jumpstart on Helm and even K8s:

- A Helm "chart" describes a packaging of templates that can render to a set of K8s resources that can be deployed to a cluster.
- A "chart" comes with a set of default "values" that define the default shape of the rendered K8s resources.
- A "release" of a given "chart" is an instantiation of the chart with a set of associated values that can re-shape the resultant K8s resources that are deployed.  When you install a "release", make sure to only supply values that you want to override.  Do **NOT** copy the entire set of default values.
- A "release" will target a given namespace in the cluster.  Some charts may deploy cluster-wide resources, but this Ignition chart does not.
- The first installation of a "release" creates the resources in the cluster, and binds them to a "revision" of the release, starting with "1".  You can "upgrade" a release and Helm will modify the K8s resources accordingly with any changes from the chart.  The history of these releases are stored by Helm in a `Secret` resource.
- All of the resources that are created with a "release" are tracked via labels, giving "Helm" the ability to manage the resources it creates, including modifying or removing them.  This binding is one of the reasons why Helm is referred to as a _package manager_ for Kubernetes.

### Single Gateway Deployment

> [!NOTE]
> As mentioned in the header, this example will provide some additional manual steps that will be omitted in the later examples.

This initial example will deploy a single gateway using a separately defined admin password.

First, let's create a namespace for our deployment.  This can be handled by Helm as well, but we'll create it explicitly for
this first example:

```bash
kubectl create namespace ignition-test
```

Update our current context to target the new namespace.  This will ensure that all of our `kubectl` commands find the resources we're deploying via Helm:

```bash
kubectl config set-context --current --namespace=ignition-test
```

Next, let's create a shared secret for our admin password.  We'll override the Helm charts values to point to this separate secret that we're managing outside of our Helm release.  We'll call the [Secret][Secret] `gateway-admin-password` (with a samely named key).  We'll set the password to `levelup` for the demo.

```bash
kubectl create secret generic gateway-admin-password --from-literal=gateway-admin-password=levelup
```

We're now ready to create a `custom-values.yaml` file that will contain the chart configuration:

```yaml
commissioning:
  # Automate acceptance of the Ignition EULA
  acceptIgnitionEULA: "Y"

  # Set the edition
  edition: standard

  auth:
    # Tie into the secret we created above
    existingSecret: gateway-admin-password

gateway:
  # TESTING ONLY - This setting will delete the PVC (data volumes) when
  # the release is uninstalled.  If this isn't specified, the PVCs will
  # remain after the release is uninstalled to prevent accidental data loss.
  persistentVolumeClaimRetentionPolicy: Delete

ingress:
  # Specify the domain suffix used for the ingress configuration, this 
  # default is useful for local development.
  domainSuffix: "localtest.me"
```

Finally, let's install a release of the Ignition chart called `ignition-test` with our custom values:

```bash
helm upgrade --install ignition-test inductiveautomation/ignition --values custom-values.yaml
```

> [!TIP]
> You can use `--debug` and `--dry-run` flags with the above to preview the rendered YAML manifests prior to installing the release in the cluster.

At this point, the release is installed and you should see the following with `kubectl get all`:

```
$ kubectl get all
NAME                          READY   STATUS    RESTARTS   AGE
pod/ignition-test-gateway-0   1/1     Running   0          53s

NAME                    TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                      AGE
service/ignition-test   ClusterIP   None         <none>        8060/TCP,8088/TCP,8043/TCP   53s

NAME                                     READY   AGE
statefulset.apps/ignition-test-gateway   1/1     53s
```

> [!TIP]
> When you run `kubectl get all`, you aren't actually viewing _all_ of the resources in the namespace.  You won't see resources such as ConfigMap, Secret, PersistentVolumeClaim, Ingress and more.  You can query those individually, i.e. `kubectl get cm,secret,pvc,ingress`.

If you're running a local dev cluster, you should now be able to bring up the gateway webpage by visiting http://ignition-test.localtest.me, based on the supplied `ingress.domainSuffix` value. 

To remove the release, you can use `helm uninstall`:

```bash
helm uninstall ignition-test
```

### Redundancy w/ GAN Certificate Integration

This configuration will enable redundancy and use cert-manager to automate GAN certificate issuance.

```yaml
# custom-values.yaml
commissioning:
  acceptIgnitionEULA: "Y"
  edition: standard
  auth:
    existingSecret: gateway-admin-password

gateway:
  redundancy:
    enabled: true

certManager:
  enabled: true

ingress:
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
  tls:
    enabled: true
```

If you install this release as `backend` (instead of `ignition-test`), you'll be able to access the gateways via:
- https://backend-ignition-primary.localtest.me
- https://backend-ignition-backup.localtest.me

### Expose directly via LoadBalancer Service

This configuration will directly expose a redundant pair of Ignition Gateways via Load Balancer services.  Additionally, this demonstrates how to tie into an existing cert-manager `ClusterIssuer` for issuing TLS certificates into Ignition.

```yaml
commissioning:
  acceptIgnitionEULA: "Y"
  disableQuickstart: false
  auth:
    existingSecret: gateway-admin-password

gateway:
  redundancy:
    enabled: true

  # We'll enable setting of Ignition Public Address Settings to align with
  # Note: these default to port 80/443, which we'll set further below
  primaryPublicAddress:
    host: demo-primary.example.com
  backupPublicAddress:
    host: demo-backup.example.com

  # We're enabling TLS, more on this in the cert-manager integration below
  tls:
    enabled: true

certManager:
  enabled: true

  # We're going to reference an existing issuer, so no need to create one.
  tlsIssuer:
    create: false

  # Details on our custom certificate
  tlsCertificate:
    spec:
      commonNameOverride: demo.example.com
      
      dnsNames:
      - demo.example.com
      - demo-primary.example.com
      - demo-backup.example.com

      # Substitute this for your own ClusterIssuer, like this one that 
      # is tied into Let's Encrypt.  NOTE: start with staging certs until
      # you've verified your configuration!
      issuerRefName: letsencrypt-staging

# Since we're exposing the Gateways directly, we won't use Ingress
ingress:
  enabled: false

# The behavior of LoadBalancer (and how it allocates external IPs) varies
# based on provider.  As one example, this example could be deployed to 
# a K3s cluster with MetalLB installed to provide each gateway with its own
# IP address on the local network.
service:
  type: LoadBalancer
  loadBalancerPorts:
    http: 80
    https: 443
```

## More resources

Check out the Ignition Helm Chart documentation at https://charts.ia.io for more information, deep dives, and additional examples.

[Secret]: https://kubernetes.io/docs/concepts/configuration/secret/
