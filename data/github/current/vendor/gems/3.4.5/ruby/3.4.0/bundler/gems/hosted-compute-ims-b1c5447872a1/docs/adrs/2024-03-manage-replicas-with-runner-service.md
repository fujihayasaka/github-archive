# Manage replicas with Runner service

## Status
Accepted

## Context

IMS stores images in [Azure Compute Galleries](https://learn.microsoft.com/en-us/azure/virtual-machines/azure-compute-gallery).

For every image version in a compute gallery, we need to configure and regularly update replications and replicas count based on current VM usage.  

The number of replicas define how many VMs can use specific image version concurrently.  Right now, in Runner service we set 1 replica per 250 VMs.

For example, for a specific image version assume it is used by

1000 VMs in eastus -> It means IMS need to set 4 replicas in eastus (1000 VMs / 250)
2300 VMs in westus -> It means IMS need to set 10 replicas in westus (2300 VMs / 250)

IMS needs to be reactive to current VM usage in order to regularly update replica counts.

As a part of the design phase of the image replication process within IMS, we opted for a strategy that would allow the service to be flexible enough to work with the current Runner Service and possible be adopted by future four-nine services such as Oracle, Runner Config:

## Proposal

There are two main components to this proposal.

### Retrieving data from the Runner Service


- Each environment (Internal, Production) will have a instance of the IMS replication job and will be connected to specific Runner scale units.
- Therefore, each Runner scale unit unit will be linked to a single IMS instance. And each IMS instance will be connected to multiple Runner scale units in it's environment:
    - `ims-internal` -> `runnerghubeus20`
    - `ims-internal` -> `runnerghubeus21`
    - `ims-production` -> `runnerghubeus1`
    - `ims-production` -> `runnerghubwus31`
    - `ims-proxima` -> `runnerproxweu1`

- Additionally, the API Contract will need to include the following request/response structures:
    - The request will include information to retrieve replication data in batches. Specifically, one request will fetch replication info for all versions of a specific image (imageId).
    - The runner service api will be a deployment level API and will reuse the existing methods being used in the ReplicationService in Runner today.
      - [Runner Code](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/RunnerImageUsageService.cs)
      - [SQL Stored Procedure](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Sql/Subscription/SProcs/prc_GetInUseImageIdCounts.sql)

```
request:

GET https://runnerghubeus1.actions.githubusercontent.com/_api/.../replication
{
    image_definition_id: int
}

response:

"image_versions":
 [
   {
      "version":"1.0.0",
      "vmcount_per_region":{
         "eastus":1000,
         "westus":2300
      }
   },
   {
      "version":"2.0.0",
      "vmcount_per_region":{
         "eastus":1200,
         "westus":2500
      }
   }
]   

```

### How the functionality will be implemented in IMS.

- This new feature will be incorporated into IMS and executed via a Cron Job. This will be constructed using [Kubernetes CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/). 
- The decision to utilize Kubernetes CronJobs was influenced by extensive investigation and consultation within Go channels. Moda apps, being stateless, posed challenges in implementing background jobs, leading to exploration of alternative solutions.
- While various libraries allow cron tasks on the application level, concerns arose regarding stability during app redeployment due to memory-stored job state and developing a custom job system with database-stored job data was considered overly complex for our requirements.
- The prevalence of Kubernetes cron job approach among similar services, such as Launch and actions-results, and widespread adoption in various projects, indicated its reliability and suitability for our needs
- The frequency of the Cron Job will be set at a 30 minute interval based on the current similar job in the Runner Service. As the new job is implemented, the frequency will be adjusted accordingly to ensure maximum efficiency.
- The API endpoint for every Runner scale unit will be stored in a configuration file.
- Authorization/Autentication will be done the same way it's handled today for calls from Launch to Runner utilizing HMAC. 
- Subsequently, the job initiates API calls to each scale unit, retrieving data and agreegates the
    incoming data and updates the database based on image_id, image_version, and region.

- The table structure for the database that will store the data retrieved from the Runner Service will be as follows:


Replica Aggregation Table
> | image_id | image_version | region | vmcount  | replica_count |
> |----------|----------|---------------|------------|----------------|
> |  4        | 1.0.0 | eastus   | 1000  | 5 |
> |  4 | 2.0.0 | westus   | 3000  | 10 |


The following is a step-by-step breakdown of the process will happen by the Cron Job:

Step 1:

The IMS Job initiates by sequentially reading through the internal image definition database and invokes the scale unit 1 (Internal) API endpoint to retrieve the following records:.

```
{image_id: 4, image_version: '1.0.0', vmcount_per_region: { eastus: 1000, westus: 2300 }},
{image_id: 4, image_version: '2.0.0', vmcount_per_region: { eastus: 500, westus: 2000 }}
```

Step 2:

IMS aggregates the data from all the retrieved records, computes the replica_count, and saves the data to the database.

> The calculation used:

> ` replica_count = aggregated (vmcount_per_region)  /  250
`
> | image_id | image_version | region | vmcount  | replica_count |
> |----------|----------|---------------|------------|----------------|
> |  4        | 1.0.0 | eastus   | 1000  | 4 |
> |  4        | 1.0.0 | westus   | 2300  | 10 |
> |  4 | 2.0.0 | westus   | 500  | 2 |
> |  4 | 2.0.0 | eastus   | 2000  | 8 |

Step 3:

If there are other scale units in this environment, the IMS Job will utilize the current image_id to iterate through the first two steps for each scale unit.

Step 4:

Once all scale units have updated the database, the Job proceeds to invoke the Azure API and update the Image Version Replica Count with the aggregated data. Utilizing Kubernetes CronJobs alleviates concerns regarding prolonged Azure processes, as the Job is capable of running for an extended duration. If required, the Job can be parallelized to manage these lengthy processes effectively.

Step 5:

Subsequently, the Job progresses to the next image_id and repeats the entire process

## Scale Down Unused Replicas
- Scaling down relies on events received from calls to the runner service API for scale units.
  - Example scenario:
      - Upon API call to SU-1, 
      1. IMS receives:
         - Image ID: 5
         - Version: 1.0.1
         - Region: eastus
         - Replica Count: 0
      2. MS updates Azure with this data.
      3. Subsequent calls without additional information maintain the Replica Count at 0.
- If new data is received for the same item, IMS updates the Replica Count accordingly.
- In cases where the Version is absent from the response:
   - IMS considers it as not in use, implying zero active VMs.
   - IMS proceeds to scale down replicas.

## Migration Plan

- The replication job will retrieve information from Runner regarding VMs from all pools that have already been migrated to new IMS images. 
- The existing runner replication system will retrieve information from Runner about VMs from all pools that are still utilizing old Runner images. Subsequently, we will proceed to migrate pools individually, one by one.

## Conclusions

By adopting this approach, we effectively address the challenge of managing data from multiple sources. Our solution enables our application to exercise control over the sources and orchestrate calls to retrieve the necessary data. This data is then directed back to an IMS table for aggregation purposes and subsequent updates to Azure services.

Additionally, this approach effectively resolves the issue of scaling down unused replicas. By incorporating this methodology, we streamline the process of identifying redundant replicas. The implementation involves querying the usage of every image within the CronJob, subsequently updating Azure services or the database based on the received response.