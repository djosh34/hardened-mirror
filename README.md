# hardened-mirror

An unofficial mirror of Docker Hardened Images and Helm charts. Every night, `.github/workflows/mirror.yml` copies what `manifest.json` lists to `ghcr.io/djosh34/hardened-mirror`, under the upstream tags. The contents keep their upstream licenses.

```sh
docker pull ghcr.io/djosh34/hardened-mirror/postgres:18
helm pull oci://ghcr.io/djosh34/hardened-mirror/cert-manager-chart --version 1.21.3
```

Tags move when upstream rebuilds. Pin a digest to stay on one build.

`.github/workflows/copy.yml` copies one image by tag once, when started by hand, for a build the nightly mirror does not keep, such as an older patch release:

```sh
gh workflow run copy.yml -f image=postgres:18.6-debian13
```
