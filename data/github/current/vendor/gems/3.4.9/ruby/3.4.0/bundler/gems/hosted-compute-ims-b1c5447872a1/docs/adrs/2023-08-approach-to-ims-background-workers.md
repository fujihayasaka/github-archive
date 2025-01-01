# Approach to IMS Background Workers

## 1. Context

### Purpose

The purpose of this document is to outline the approach for implementing background workers in IMS (Image Management Service) to handle periodic and on-demand jobs for image definitions and versions.

### Background

IMS is a service that manages images and their versions. It needs to perform periodic and on-demand jobs for image definitions and versions, such as converting VHDs to Gallery Images, deleting old images, updating replications, and more. These jobs need to be executed in a reliable and scalable manner.

## 2. Requirements

The following requirements have been identified for the IMS background workers:

- Ability to run jobs on cron or on-demand for every image definition / image version.
- Ability to limit the number of parallel jobs / workers for a single IMS instance.
- Ability to synchronize jobs/workers between different instances of IMS.
- Ability to handle job failures properly (retries, failure history, etc.).
- Ability to ensure reliability and not lose jobs even if the process crashes.

## 3. Proposal

Our initial proposal is to implement IMS background workers using Go language and one of the following options:

- https://github.com/hibiken/asynq
- https://github.com/gocraft/worker
- https://github.com/github/aqueduct
- Custom implementation

The initial two choices are based on open-source solutions and have been adopted by numerous other repositories. Another possibility is to develop our own background worker system, a task demanding additional time and energy, yet offering increased authority and adaptability. Lastly, an internal tool utilized by GitHub's #data-pipelines teams for overseeing background tasks presents itself as the final option.

### Similarities of the packages

- All of the packages utilize Redis as a backend for job queuing and management.
- They provide a simple way to start and manage a pool of workers that can execute jobs concurrently.
- They also include a job queue that enqueues jobs to be executed by a worker.
- They can handle background job failures by retrying failed jobs and keeping a failure history.
- These solutions will also ensure reliability and prevent job loss even if the process crashes.
- Middleware on jobs -- good for metrics instrumentation, logging, etc.
- Schedule jobs to happen in the future.
- Pause / unpause jobs and control concurrency within and across processes

The following diagram shows the proposed high level architecture of the IMS background workers:

![Background Process](/docs/assets/background-process.png)

### 3.1. Option 1: The asynq package

- Package repo statistics:
  - 498 forks
  - 6.6k stars
  - 32 contributors

#### 3.1.1. Advantages

- The asynq package has a simple and easy-to-use API that allows you to define tasks and handlers.
- The package integrates seamlessly with Redis, a popular in-memory data store that provides fast and reliable message queuing and management.
- The package provides built-in support for controlling concurrency, allowing you to limit the number of workers and the number of tasks that can be processed concurrently.
- The package supports middleware, which allows you to add additional functionality to your tasks and handlers, such as logging, metrics, and error handling.
- The package provides built-in support for retrying failed tasks and handling errors, ensuring that your background jobs are executed reliably and with minimal manual intervention.
- The package provides a interface to allow you to implment a custom storage backend for job queuing and management, allowing you to use different storage systems for job queuing and management, such as Redis, PostgreSQL, or in-memory storage.

#### 3.1.2. Drawbacks

- The package has a disclaimer that the library is undergoing heavy development with frequent API changes.  

### 3.2. Option 2: The gocraft/worker package

- Package repo statistics:
  - 306 forks
  - 2.2k stars
  - 18 contributors

#### 3.2.1. Advantages

- The gocraft/worker package has a simple and easy-to-use API that allows you to define tasks and handlers.
- The package provides built-in support for controlling concurrency, allowing you to limit the number of workers and the number of tasks that can be processed concurrently.
- The package supports middleware, which allows you to add additional functionality to your tasks and handlers, such as logging, metrics, and error handling.
- The package provides built-in support for scheduling jobs to run at a specific time or after a specific delay.
- The package supports pluggable backends, allowing you to use different storage systems for job queuing and management, such as Redis, PostgreSQL, or in-memory storage.

#### 3.2.2. Drawbacks

- The packages repo has not beeen updated in 2 years. Last commit was on 2020-06-29.

### 3.3. Option 3: Custom implementation

#### 3.3.1. Advantages

- A custom message broker can be tailored to our specific use case and requirements, allowing us to implement features and functionality that may not be available in existing message brokers.
- A custom message broker can be optimized for our specific workload, potentially providing better performance and scalability than a general-purpose message broker.
- We can integrated a custom tool more tightly with our existing systems and infrastructure, providing a more seamless and efficient workflow.
- Gives us full control over the implementation and operation of the message queue, allowing us to fine-tune performance, security, and other aspects of the system.
- Writting this can be a valuable learning experience, allowing us to deepen our understanding of distributed systems, messaging patterns, and Go language.

#### 3.3.2. Drawbacks

- Developing a library from scratch will require a significant amount of time.
- Supporting and maintaining a custom library will require additional time and effort.

### 3.4. Option 4: The aqueduct package

- Package repo statistics:
  - 0 forks
  - 5 stars
  - 21 contributors

#### 3.4.1. Advantages

- This package is written and maintained by a Github team and is intergrated with Github's internal systems.
- This package is currently used in production by other Github teams and would not need to be deployed and maintained by the IMS team.
- Exposes a Twirp API, which provides a protobuf RPC definitions, client code generation in many languages, and both JSON and protobuf support.
- Logs all job lifecycle events to Hydro and the data warehouse for optimal observability.
- Persists all job payloads to the data warehouse for easy auditing, debugging and job replay.
- Offers granular worker resource controls through queue pausing work and throttling via chatops.
- Automatically redelivers lost jobs.

#### 3.4.2. Drawbacks

- This package is not managed by the IMS team and would require the IMS team to rely on another team to maintain and support any required changes.
- Makes the solution not self-contained.

## 4. Coding Examples

The following coding examples illustrate how similar the 2 packages are to implement a simple broker service.  

- **Setup Message Broker/Queue (Redis)**

    This example will do the following:
  - Create a Redis connection.
  - Create a message broker.
  - Register a task or job handler function with the message broker.
  - Start the message broker.

**NOTE** - Using Aqueduct does not require a message broker to be setup.  We are just registering the job handler function with the aqueduct worker.

Using asynq:

 ```go
    package main

    import (
        "context"
        "fmt"
        "time"

        "github.com/hibiken/asynq"
        "github.com/hibiken/asynq/redis"
    )

    func main() {
        // Create a Redis connection.
        redisConn := redis.NewClient(&redis.Options{
            Addr:     "localhost:26379",
            Password: "",
            DB:       0,
        })

        // Create a new Asynq server.
        server := asynq.NewServer(
            asynq.RedisClientOpt{Client: redisConn},
            asynq.Config{
                Concurrency: 10,
                Queues: map[string]int{
                    "defaultQ": 1,
                    "MoveImagesQ": 2,
                },
            },
        )

        // Define a task handler function.
        taskMoveImagesHandler := func(ctx context.Context, task *asynq.Task) error {
            fmt.Printf("Processing task %s...\n", task.Type)
            time.Sleep(5 * time.Second)
            fmt.Printf("Task %s processed.\n", task.Type)
            return nil
        }

        // Register the task handler function.
        h := asynq.HandlerFunc(taskMoveImagesHandler)
        server.SetHandler(h, "MoveImagesQ")

        // Start the Asynq server.
        server.Run()
    }

 ```

Using gocraft/worker:

 ```go
    import (
        "github.com/gocraft/worker"
        "github.com/gomodule/redigo/redis"
    )

    // Define a job handler function
    func moveImagesHandler myHandler(job *worker.Job) error {
        // Process the job here
        return nil
    }

    // Define a custom message broker struct
    type RedisBroker struct {
        pool *redis.Pool
    }

    // Implement the worker.EnqueueFunc interface for the RedisBroker struct
    func (b *RedisBroker) Enqueue(queue string, job *worker.Job) error {
        conn := b.pool.Get()
        defer conn.Close()

        // Serialize the job data as JSON
        data, err := json.Marshal(job)
        if err != nil {
            return err
        }

        // Add the job data to the Redis list for the specified queue
        _, err = conn.Do("RPUSH", "worker:queue:"+queue, data)
        if err != nil {
            return err
        }

        return nil
    }

    // Create a new RedisBroker instance
    broker := &RedisBroker{
        pool: &redis.Pool{
            Dial: func() (redis.Conn, error) {
                return redis.Dial("tcp", "localhost:26379")
            },
        },
    }

    // Create a new worker pool with a single queue and the custom RedisBroker
    pool := worker.New(broker, map[string]worker.JobHandler{
        "MoveImagesQ": moveImagesHandler,
    })

    // Start the worker pool
    pool.Start()      
   ```

Using aqueduct:

 ```go
    package main

    import (
        "context"
        "fmt"

        "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
    )

    func main() {
        aqueductUrl := "http://localhost:28085"
        client, _ := aqueduct.NewClient(aqueductUrl)

        moveImagehandler := func(_ context.Context, rr aqueduct.ReceiveResult) error {
            fmt.Println("...My processing logic goes here...")
            return nil
        }

        worker, _ := aqueduct.NewWorker(
            client,
            "moveImage-app", []string{"MoveImagesQ"},
            moveImagehandler,
        )

        // go worker.ProcessJob(context.Background())
        worker.ProcessJob(context.Background())
    }

```

- **Client calling Message Broker/Queue**

    Showing how to call the message broker from a client. The examples below will show how to use a client to call the message broker and queue a new task/job on a queue named "MoveImages".

    Using asynq:

 ```go
     
     import (
         "context"
         "github.com/hibiken/asynq"
      )

     // Create a new Redis client
     redisClient := asynq.NewRedisClient("localhost:26379", 0, "")

      // Create a new task
      task := asynq.NewTask("task_1", nil)
      task.Queue = "MoveImages"

      // Add the task to the queue
       asynq.Enqueue(redisClient, task)
    

   ```

Using gocraft/worker:

 ```go

    import "github.com/gocraft/worker"

    // Define a job handler function
    func myHandler(job *worker.Job) error {
        // Process the job here
        return nil
    }

    // Create a new Redis pool
    redisPool := worker.NewRedisPool("localhost:26379")

    // Create a new job
    job := worker.Job{
        Name: "task_1",
        Queue: "MoveImages",
        Handler: myHandler,
    }

    // Add the job to the queue
    worker.Enqueue(redisPool, job)   
   ```

Using aqueduct:

 ```go

    package main

    import (
        "context"
        "fmt"
        "time"

        "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
    )

    func main() {
        aqueductUrl := "http://localhost:28085"
        app := "task_1"
        queue := "MoveImages"

        client, _ := aqueduct.NewClient(aqueductUrl)
        
        // Sending a job to Aqueduct
        job := aqueduct.Job{App: app, Queue: queue, Payload: []byte("test payload")}
        client.Send(context.Background(), job)
        
        // Receiving a job from Aqueduct
        rr, _ := client.Receive(context.Background(), app, []string{queue}, 1*time.Second)

        fmt.Println("Receive result:", rr)
    }
```

## Conclusion

After evaluating the 4 options, our primary recommendation is to use the aqueduct package.

The aqueduct package meets or exceeds all requirments and provides a simple and easy-to-use API, currently being used in production by other Github teams.

Our secondary recommendation is to use the asynq package.

The asynq package provides a simple and easy-to-use API, seamless integration with Redis, built-in support for concurrency control, middleware, retry and error handling, extensibility through custom storage backends, and is actively maintained.

The `` gocraft/worker `` package also provides many of the same features but hasn't been updated in 2 years which indicates that it is no longer actively maintained.

## Decision

Following the recent ADR review meeting, the decision is in favor of using Aqueduct for IMS Background Workers. However, it's noted that Aqueduct lacks native support for a cron-based job scheduler. To address this, a simple automation will be created and triggered on service start and every 10 minutes. This automation will handle scheduling daily jobs, with Aqueduct ensuring that only one job is 
scheduled at a time.
