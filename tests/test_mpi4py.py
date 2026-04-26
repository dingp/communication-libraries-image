#!/usr/bin/env python3

from mpi4py import MPI
import random
import socket
import time


def main():
    # Initialize MPI
    comm = MPI.COMM_WORLD
    rank = comm.Get_rank()
    size = comm.Get_size()

    # Get hostname to identify which node each rank is running on
    hostname = socket.gethostname()

    # Print basic info from each rank
    print(f"Rank {rank}/{size} running on node: {hostname}")

    # Barrier to synchronize output
    comm.Barrier()

    if rank == 0:
        print("\n=== MPI Test Program ===")
        print(f"Total ranks: {size}")
        print("Expected: 32 ranks across 2 nodes (16 per node)")
        print("=" * 50)

    comm.Barrier()

    # Test 1: Gather hostnames to see distribution
    all_hostnames = comm.gather(hostname, root=0)

    if rank == 0:
        print("\nTest 1: Node Distribution")
        node_count = {}
        for i, host in enumerate(all_hostnames):
            if host not in node_count:
                node_count[host] = []
            node_count[host].append(i)

        for node, ranks in node_count.items():
            print(f"Node {node}: {len(ranks)} ranks - {ranks}")

    comm.Barrier()

    # Test 2: Collective communication - Allreduce
    if rank == 0:
        print("\nTest 2: Collective Communication (Allreduce)")

    local_value = rank + 1
    global_sum = comm.allreduce(local_value, op=MPI.SUM)

    if rank == 0:
        expected_sum = size * (size + 1) // 2
        print(f"Sum of all ranks: {global_sum} (expected: {expected_sum})")
        print(f"Test {'PASSED' if global_sum == expected_sum else 'FAILED'}")

    comm.Barrier()

    # Test 3: Point-to-point communication (using non-blocking)
    if rank == 0:
        print("\nTest 3: Point-to-Point Communication")

        # Send data to all other ranks using non-blocking sends
        data = list(range(1000))  # List of integers 0-999
        send_requests = []
        for dest in range(1, size):
            req = comm.isend(data, dest=dest, tag=100)
            send_requests.append(req)

        # Wait for all sends to complete
        MPI.Request.waitall(send_requests)
        print(f"Rank 0 sent data to ranks 1-{size - 1}")

        # Receive results back using non-blocking receives
        recv_requests = []
        results = [None] * (size - 1)
        for i, source in enumerate(range(1, size)):
            req = comm.irecv(source=source, tag=200)
            recv_requests.append((req, i))

        # Wait for all receives to complete
        for req, i in recv_requests:
            results[i] = req.wait()

        print(f"Rank 0 received {len(results)} results back")

    else:
        # Receive data from rank 0 using non-blocking receive
        req = comm.irecv(source=0, tag=100)
        data = req.wait()

        # Process data (compute sum) and send back using non-blocking send
        result = sum(data)
        req_send = comm.isend(result, dest=0, tag=200)
        req_send.wait()

    comm.Barrier()

    # Test 4: Broadcast and timing
    if rank == 0:
        print("\nTest 4: Broadcast Performance")
        # Create random data
        random.seed(42)
        broadcast_data = [random.random() for _ in range(10000)]
    else:
        broadcast_data = None

    start_time = MPI.Wtime()
    broadcast_data = comm.bcast(broadcast_data, root=0)
    end_time = MPI.Wtime()

    # Gather timing results
    timing = end_time - start_time
    all_timings = comm.gather(timing, root=0)

    if rank == 0:
        avg_time = sum(all_timings) / len(all_timings)
        max_time = max(all_timings)
        print(f"Broadcast of 10k floats - Avg time: {avg_time:.6f}s, Max time: {max_time:.6f}s")

    comm.Barrier()

    # Test 5: Scatter/Gather operations
    if rank == 0:
        print("\nTest 5: Scatter/Gather Operations")
        # Create data to scatter (each rank gets a chunk)
        scatter_data = [list(range(i * 100, (i + 1) * 100)) for i in range(size)]
    else:
        scatter_data = None

    # Scatter data
    local_chunk = comm.scatter(scatter_data, root=0)

    # Process local chunk (compute mean)
    local_result = sum(local_chunk) / len(local_chunk)

    # Gather results
    all_results = comm.gather(local_result, root=0)

    if rank == 0:
        print(f"Gathered {len(all_results)} results from scatter/gather test")
        print(f"Sample results: {all_results[:5]}...")

    comm.Barrier()

    # Test 6: Ring communication pattern
    if rank == 0:
        print("\nTest 6: Ring Communication Pattern")

    # Each rank sends to next rank in ring
    send_rank = (rank + 1) % size
    recv_rank = (rank - 1) % size

    send_data = f"Message from rank {rank}"

    # Use non-blocking communication to avoid deadlock
    req_send = comm.isend(send_data, dest=send_rank, tag=300)
    req_recv = comm.irecv(source=recv_rank, tag=300)

    # Wait for completion
    req_send.wait()
    received_data = req_recv.wait()

    # Gather all received messages
    all_messages = comm.gather(received_data, root=0)

    if rank == 0:
        print("Ring communication completed")
        print(f"Sample messages: {all_messages[:3]}...")

    comm.Barrier()

    # Test 7: Reduction with custom operation
    if rank == 0:
        print("\nTest 7: Custom Reduction (Max and Min)")

    local_random = random.randint(1, 1000)

    global_max = comm.allreduce(local_random, op=MPI.MAX)
    global_min = comm.allreduce(local_random, op=MPI.MIN)

    if rank == 0:
        print(f"Global max: {global_max}, Global min: {global_min}")

    comm.Barrier()

    # Test 8: Barrier timing test
    if rank == 0:
        print("\nTest 8: Barrier Synchronization Test")

    # Simulate different work times
    work_time = 0.001 * (rank % 5)  # 0-4ms of work
    time.sleep(work_time)

    start_barrier = MPI.Wtime()
    comm.Barrier()
    end_barrier = MPI.Wtime()

    barrier_times = comm.gather(end_barrier - start_barrier, root=0)

    if rank == 0:
        avg_barrier_time = sum(barrier_times) / len(barrier_times)
        max_barrier_time = max(barrier_times)
        print(f"Barrier sync - Avg time: {avg_barrier_time:.6f}s, Max time: {max_barrier_time:.6f}s")

    comm.Barrier()

    if rank == 0:
        print("\n" + "=" * 50)
        print("All MPI tests completed successfully!")
        print("=" * 50)


if __name__ == "__main__":
    main()
