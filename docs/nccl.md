# NCCL

NCCL is GPU-only in this repository. The `nccl-gpu` target layers NCCL and the AWS OFI NCCL plugin on the combined OpenMPI OFI+UCX GPU image.

Image target:

- `nccl-gpu`

Stack:

```text
NCCL collectives
  |
  +-- AWS OFI NCCL plugin
        |
        +-- libfabric OFI
              |
              +-- cxi provider
                    |
                    +-- Slingshot/Cassini
```

Default environment:

```bash
NCCL_NET="AWS Libfabric"
NCCL_CROSS_NIC=1
NCCL_SOCKET_IFNAME=hsn
NCCL_NET_GDR_LEVEL=PHB
NCCL_NCHANNELS_PER_NET_PEER=4
FI_PROVIDER=cxi
FI_CXI_DISABLE_HOST_REGISTER=1
FI_MR_CACHE_MONITOR=userfaultfd
```

Test command:

```bash
scripts/run-perlmutter.sh gpu nccl
```
