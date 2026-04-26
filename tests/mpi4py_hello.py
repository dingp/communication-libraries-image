from mpi4py import MPI


comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()
name = MPI.Get_processor_name()

all_names = comm.allgather(name)
if rank == 0:
    unique_names = sorted(set(all_names))
    print(f"mpi4py hello: {size} ranks across {len(unique_names)} nodes: {', '.join(unique_names)}")

