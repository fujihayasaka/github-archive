# Aqueduct Jobs

Licensify uses Aqueduct jobs to manage long-running processes. These jobs are enqueued
either internally by another process or externally through Aqueduct Bridge.

Aqueduct jobs give us the benefit of offloading intensive processes to a separate
worker, allowing things like Hydro handlers or API requests to return quickly. Aqueduct
also offers the flexibility to control how many worker nodes run to process events which
allows us to easily scale the service to handle varying volumes of events.

## Creating a new job

1. Implement a new handler in `internal/aqueduct/handlers/<your_handler_name>_handler.go`.
2. Add a new `const` to `internal/aqueduct/jobs/jobs.go`.
3. Add a new `const` to `internal/aqueduct/queues/queues.go`. Make sure this value gets
  added to the `Queues` slice which will register the queue with the Aqueduct consumer. 
4. When enqueuing the new job, use the queue const as the job queue and the job const
  as the header value.
