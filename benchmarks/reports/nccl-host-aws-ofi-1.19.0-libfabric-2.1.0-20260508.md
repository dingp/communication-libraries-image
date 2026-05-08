# Host NCCL Test With aws-ofi-nccl 1.19.0 And libfabric 2.1.0

This note records a host-side Perlmutter build and test of NCCL plus aws-ofi-nccl using a scratch-built libfabric that matches the container images in this repository.

## Summary

| Component | Version or setting |
| --- | --- |
| CUDA module | `cudatoolkit/13.0` |
| MPI | Cray MPICH from the Perlmutter programming environment |
| libfabric | `v2.1.0`, scratch-built with CXI, LNX, CUDA, GDRCopy, and XPMEM support |
| NCCL | `v2.29.2-1`, built from source |
| aws-ofi-nccl | `v1.19.0`, built against the scratch libfabric |
| nccl-tests | MPI-enabled build of `all_reduce_perf` |
| Test | `all_reduce_perf -b 8 -e 4G -f 2` |
| Placement | 2 GPU nodes, 4 ranks per node, 8 total ranks |

The scratch libfabric build was verified with:

```text
fi_info: 2.1.0
libfabric: 2.1.0
libfabric api: 2.1
```

`libnccl-net.so` resolved libfabric from the scratch install:

```text
libfabric.so.1 => $RUN_ROOT/install-libfabric-2.1.0/lib/libfabric.so.1
```

## Findings

| Run | Key environment | Result |
| --- | --- | --- |
| Default aws-ofi-nccl 1.19.0 | DMA-BUF enabled, `NCCL_NET_GDR_LEVEL=PHB` | Failed |
| No DMA-BUF | `OFI_NCCL_DISABLE_DMABUF=1`, `NCCL_NET_GDR_LEVEL=PHB` | Passed |

Both runs selected the CXI provider and SENDRECV transport:

```text
NET/OFI Initializing aws-ofi-nccl 1.19.0
NET/OFI Using Libfabric version 2.1
NET/OFI Selected provider is cxi, fabric is cxi (found 4 nics)
NET/OFI Using transport protocol SENDRECV
```

The default DMA-BUF path failed after connection setup with small receive completions returning `NO_SPACE`:

```text
NET/OFI Support for DMA-BUF registrations: true
NET/OFI Request ... completed with error. RC: 5. Flags: 260. Error: 16 (NO_SPACE).
Request: { dev: 3, size: 4, state: CREATED, direction: RECV }
```

With `OFI_NCCL_DISABLE_DMABUF=1`, the run completed:

```text
NET/OFI Support for DMA-BUF registrations: false
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 23.0033
# Collective test concluded: all_reduce_perf
```

The 4 GiB row from the successful run:

```text
bytes        count       type   redop  root   time(us) algbw busbw errors time(us) algbw busbw errors
4294967296   1073741824 float  sum    -1     104054   41.28 72.23 0      103495   41.50 72.62 0
```

Conclusion: using libfabric 2.1.0 on the host does not by itself fix the aws-ofi-nccl 1.19.0 default DMA-BUF path on the tested Perlmutter stack. For this stack, keep `OFI_NCCL_DISABLE_DMABUF=1` when using aws-ofi-nccl 1.19.0 with CXI/SENDRECV.

## Build Instructions

Create a scratch run directory:

```bash
RUN_ROOT="${SCRATCH}/communication-libraries-image/nccl-ofi-plugin-runs/$(date -u +%Y%m%dT%H%M%SZ)-aws-ofi-1.19.0-libfabric-2.1.0"
mkdir -p "${RUN_ROOT}"
cd "${RUN_ROOT}"
```

Create `build_libfabric_nccl.sh`:

```bash
cat > build_libfabric_nccl.sh <<'EOF'
#!/bin/bash
#SBATCH -C gpu
#SBATCH -A <account>
#SBATCH -q <gpu_qos>
#SBATCH --nodes=1
#SBATCH --gpus-per-node=4
#SBATCH --time=00:45:00
#SBATCH -o slurm-build-libfabric-nccl-%j.out

set -euxo pipefail

module load cudatoolkit/13.0
module unload craype-accel-nvidia80 || true

ROOT=${ROOT:-$(pwd)}
LIBFABRIC_VERSION=${LIBFABRIC_VERSION:-2.1.0}
NCCL_BRANCH=${NCCL_BRANCH:-v2.29.2-1}
AWSOFINCCL_BRANCH=${AWSOFINCCL_BRANCH:-v1.19.0}
NCCL_TESTS_REPO=${NCCL_TESTS_REPO:-https://github.com/NVIDIA/nccl-tests.git}
N=${N:-10}

LIBFABRIC_HOME=${LIBFABRIC_HOME:-${ROOT}/install-libfabric-${LIBFABRIC_VERSION}}
INSTALL_DIR=${INSTALL_DIR:-${ROOT}/install}
PLUGIN_DIR=${PLUGIN_DIR:-${INSTALL_DIR}/plugin}
NCCL_HOME=${NCCL_HOME:-${INSTALL_DIR}}

export CUDA_HOME=${CUDA_HOME:?CUDA_HOME is not set by cudatoolkit module}
export CUDATOOLKIT_HOME=${CUDATOOLKIT_HOME:-${CUDA_HOME}}
export LIBFABRIC_HOME INSTALL_DIR PLUGIN_DIR NCCL_HOME
export PATH="${LIBFABRIC_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${LIBFABRIC_HOME}/lib:${LIBFABRIC_HOME}/lib64:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="${LIBFABRIC_HOME}/lib/pkgconfig:${LIBFABRIC_HOME}/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
export MPI_HOME=${MPI_HOME:-${CRAY_MPICH_DIR:?CRAY_MPICH_DIR is not set}}
export NVCC_GENCODE=${NVCC_GENCODE:-"-gencode=arch=compute_80,code=sm_80"}
export MPICC=CC
export CC=gcc
export CXX=g++
export MPICH_GPU_SUPPORT_ENABLED=0

cd "${ROOT}"

if [[ ! -d libfabric ]]; then
  git clone --branch "v${LIBFABRIC_VERSION}" --depth 1 https://github.com/ofiwg/libfabric.git
fi
cd libfabric
./autogen.sh
./configure --prefix="${LIBFABRIC_HOME}" --with-cuda="${CUDA_HOME}" \
  --enable-cuda-dlopen --enable-gdrcopy-dlopen --enable-cxi --enable-lnx \
  --enable-xpmem=/usr
make -j "${N}"
make install
"${LIBFABRIC_HOME}/bin/fi_info" --version
cd "${ROOT}"

if [[ ! -d nccl ]]; then
  git clone --branch "${NCCL_BRANCH}" https://github.com/NVIDIA/nccl.git
  cd nccl
  make -j "${N}" PREFIX="${NCCL_HOME}" src.build
  make PREFIX="${NCCL_HOME}" install
  cd "${ROOT}"
fi

if [[ ! -d aws-ofi-nccl ]]; then
  git clone -b "${AWSOFINCCL_BRANCH}" https://github.com/aws/aws-ofi-nccl.git
  cd aws-ofi-nccl
  ./autogen.sh
  ./configure --with-cuda="${CUDA_HOME}" --with-libfabric="${LIBFABRIC_HOME}" --prefix="${PLUGIN_DIR}" --disable-tests
  make -j "${N}" install
  cd "${ROOT}"
fi

if [[ ! -d nccl-tests ]]; then
  git clone "${NCCL_TESTS_REPO}"
  cd nccl-tests
  make -j "${N}" MPI=1 CC=cc CXX=CC NCCL_HOME="${NCCL_HOME}"
  mkdir -p "${INSTALL_DIR}/tests"
  find ./build -type f -executable -exec cp {} "${INSTALL_DIR}/tests/" \;
  cd "${ROOT}"
fi

mkdir -p "${PLUGIN_DIR}/deps/lib"
cp -P "${LIBFABRIC_HOME}"/lib/libfabric.so* "${PLUGIN_DIR}/deps/lib/" 2>/dev/null || true
cp -P "${LIBFABRIC_HOME}"/lib64/libfabric.so* "${PLUGIN_DIR}/deps/lib/" 2>/dev/null || true
cp -P /usr/lib64/libcxi.so* /usr/lib64/libcxiutils.so* /usr/lib64/libxpmem.so* /usr/lib64/libgdrapi.so* "${PLUGIN_DIR}/deps/lib/" 2>/dev/null || true

ldd "${PLUGIN_DIR}/lib/libnccl-net.so" || true
strings "${PLUGIN_DIR}/lib/libnccl-net.so" | grep -E 'aws-ofi-nccl|OFI NCCL|Libfabric' | head -20 || true
EOF
chmod +x build_libfabric_nccl.sh
```

Submit the build:

```bash
sbatch build_libfabric_nccl.sh
```

Notes:

- EFA is intentionally not enabled in this host build. Perlmutter uses CXI, and the host environment used for this test did not provide EFA headers.
- The container image still builds libfabric with EFA enabled because that dependency is available in the image build environment.

## Run Instructions

Create `run_tests_libfabric.sh`:

```bash
cat > run_tests_libfabric.sh <<'EOF'
#!/bin/bash
#SBATCH -A <account>
#SBATCH -C gpu
#SBATCH -q <gpu_qos>
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --gpus-per-node=4
#SBATCH --time=00:15:00
#SBATCH -o slurm-test-libfabric-%j.out

set -euxo pipefail

module load cudatoolkit/13.0
module unload craype-accel-nvidia80 || true

ROOT=${ROOT:-$(pwd)}
LIBFABRIC_HOME=${LIBFABRIC_HOME:-${ROOT}/install-libfabric-2.1.0}
NCCL_HOME=${NCCL_HOME:-${ROOT}/install}
NCCL_PLUGIN_HOME=${NCCL_PLUGIN_HOME:-${NCCL_HOME}/plugin}
NCCL_TESTS_HOME=${NCCL_TESTS_HOME:-${ROOT}/nccl-tests/build}

export PATH="${LIBFABRIC_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${NCCL_HOME}/lib:${NCCL_PLUGIN_HOME}/lib:${LIBFABRIC_HOME}/lib:${LIBFABRIC_HOME}/lib64:${LD_LIBRARY_PATH:-}"
export MPICH_GPU_SUPPORT_ENABLED=0
export FI_CXI_RDZV_GET_MIN=0
export FI_CXI_SAFE_DEVMEM_COPY_THRESHOLD=16777216
export FI_CXI_DISABLE_HOST_REGISTER=1
export NCCL_DEBUG=${NCCL_DEBUG:-INFO}
export NCCL_SOCKET_IFNAME=${NCCL_SOCKET_IFNAME:-hsn}
export NCCL_NET=${NCCL_NET:-AWS Libfabric}
export NCCL_NET_GDR_LEVEL=${NCCL_NET_GDR_LEVEL:-PHB}

which fi_info
fi_info --version
ldd "${NCCL_PLUGIN_HOME}/lib/libnccl-net.so" || true
ldd "${NCCL_TESTS_HOME}/all_reduce_perf" || true
env | sort | grep -E '^(FI_|NCCL_|OFI_NCCL|MPICH_GPU|LD_LIBRARY_PATH|LIBFABRIC_HOME)=' || true

srun "${NCCL_TESTS_HOME}/all_reduce_perf" -b 8 -e 4G -f 2
EOF
chmod +x run_tests_libfabric.sh
```

Run the default aws-ofi-nccl 1.19.0 path:

```bash
sbatch --output="${RUN_ROOT}/slurm-test-libfabric-%j.out" \
  --export=ALL \
  run_tests_libfabric.sh
```

This is expected to fail on the tested stack with the `NO_SPACE` receive completion shown above.

Run the working no-DMA-BUF variant:

```bash
sbatch --output="${RUN_ROOT}/slurm-test-libfabric-no-dmabuf-%j.out" \
  --export=ALL,OFI_NCCL_DISABLE_DMABUF=1 \
  run_tests_libfabric.sh
```

For comparison with the container workflow, this is the host-side setting that was carried into the `bench-nccl-mpich-gpu` image and Perlmutter benchmark wrapper.
