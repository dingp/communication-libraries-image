# CXI

CXI is the user-facing interface to the HPE Slingshot/Cassini network on Perlmutter. The container images include CXI headers and `libcxi`, but the kernel driver and device files come from the host.

Relevant image pieces:

- Cassini headers from `shs-cassini-headers`
- CXI driver headers from `shs-cxi-driver`
- `libcxi` from `shs-libcxi`
- libfabric built with `--enable-cxi`

Runtime requirements:

```text
host /dev/cxi*  ->  container /dev/cxi*
host /dev/xpmem ->  container /dev/xpmem
host /dev/shm   ->  container /dev/shm
```

The run script binds all visible `/dev/cxi*` devices. On a Perlmutter login node this may be `/dev/cxi0` and `/dev/cxi1`; GPU compute nodes may expose a different set.

CXI is selected through libfabric:

```bash
FI_PROVIDER=cxi
fi_info -p cxi
```

Do not expect a container-only smoke test to find `cxi` unless the host CXI device files are mounted into the container.
