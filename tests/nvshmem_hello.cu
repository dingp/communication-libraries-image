#include <stdio.h>

#include <cuda_runtime.h>
#include <nvshmem.h>
#include <nvshmemx.h>

__global__ void write_to_next_pe(int *value) {
    int mype = nvshmem_my_pe();
    int npes = nvshmem_n_pes();
    int peer = (mype + 1) % npes;

    nvshmem_int_p(value, mype, peer);
}

int main(void) {
    nvshmem_init();

    int mype = nvshmem_my_pe();
    int npes = nvshmem_n_pes();
    int local_pe = nvshmem_team_my_pe(NVSHMEMX_TEAM_NODE);
    int device_count = 0;

    cudaGetDeviceCount(&device_count);
    if (device_count <= 0) {
        fprintf(stderr, "No CUDA devices are visible\n");
        nvshmem_finalize();
        return 1;
    }

    cudaSetDevice(local_pe % device_count);

    int *value = (int *)nvshmem_malloc(sizeof(int));
    cudaMemset(value, 0, sizeof(int));

    write_to_next_pe<<<1, 1>>>(value);
    cudaDeviceSynchronize();
    nvshmem_barrier_all();

    int host_value = -1;
    cudaMemcpy(&host_value, value, sizeof(int), cudaMemcpyDeviceToHost);

    int expected = (mype + npes - 1) % npes;
    printf("NVSHMEM hello: PE %d/%d received %d from PE %d\n",
           mype, npes, host_value, expected);

    nvshmem_free(value);
    nvshmem_finalize();

    return host_value == expected ? 0 : 2;
}
