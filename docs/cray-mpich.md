# Cray MPICH Image

`container/cray-mpich-cpe.Containerfile` is an example recipe for installing HPE Cray MPICH inside an image.

The public `container/Containerfile` targets build open-source MPICH and Open MPI from source. Cray MPICH is different: the installable artifacts come from HPE CPE repositories or a site-local mirror. Do not copy `/opt/cray` from Perlmutter into an image that will be pushed to GHCR unless the licensing and redistribution path has been explicitly approved.

Build example with a site mirror:

```bash
podman-hpc build \
  -f container/cray-mpich-cpe.Containerfile \
  --build-arg HPE_CPE_REPO_URL="${HPE_CPE_REPO_URL}" \
  --build-arg HPE_CPE_GPG_KEY_URL="${HPE_CPE_GPG_KEY_URL}" \
  -t localhost/communication-libraries-image:cray-mpich-cpu \
  .
```

The default package names are placeholders for CPE 25.09-era GNU builds:

```text
cray-mpich-9.0.1-gnu123
cray-mpich-9.0.1-gtl
cray-pmi
cray-pals
craype
```

Adjust them to match the CPE mirror packaging before enabling the GitHub Actions workflow for this target.

