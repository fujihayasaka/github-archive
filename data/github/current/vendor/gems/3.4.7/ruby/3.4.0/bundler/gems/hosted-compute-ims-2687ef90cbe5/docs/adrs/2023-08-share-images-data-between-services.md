# Share images data between services

## Status
Accepted

## Context

In 4-9s architecture Image Management Service will be responsible for image promotion and image management.

There are some other services which should be able to retrieve images data from IMS:
- LCM / Runner - these services need to retrieve [ImageReference](https://learn.microsoft.com/en-us/azure/templates/microsoft.compute/2021-03-01/virtualmachines?pivots=deployment-language-bicep#imagereference) by ImageKey (ImageSource, ImageId, ImageVersion)
- GCAS - this service needs to retrieve info about available image versions for every image definition and deployment plans
- Runner Config - this service needs to retrieve some image properties (image size, image os, etc) to validate pool on create / update operations.

We need to figure out what is the best way to share images data with all these services.

Our priorities:
1. High availability and graceful degradation - if IMS service is down, other services should be able to work with latest known images and shouldn't be impacted
2. Images data is up-to-date between all services
3. Easy to maintain, extend, support  
4. Easy to define and measure SLO metrics  
5. All resources which are participating in sharing images data should be owned by our team  

## Proposal

### Option 1 - Direct API calls to IMS service

All services will perform direct API requests to IMS service when the data is required.

\+ Simple and clear approach  
\+ Images data is always up-to-date  
\+ Easy to measure SLO metrics  
\- Low availability - if IMS is down, all dependent services will be impacted  
\- Huge load on IMS service because other services will make a lot of API calls (for example, LCM service will make a call for every VM)  

### Option 2 - Use Shared DB to access images data

We will use [Shared DB](https://github.com/github/hosted-compute#shared-db) (CosmosDB NoSQL) provided by Hosted Compute team to share the data between services. This shared DB will be separated from internal images database and will be available for all dependent services.

We will implement shared module which will be an interface for this shared database and all dependent services will consume the module to access images data.
For data consistency and contracts we will use protobuf.

\+ Data is not duplicated  
\+ Data is always up-to-date  
\+ High availability (5-9s for CosmosDB) and data is available when IMS is down  
\- Ownership of shared resources is not clear. Who will own the shared database if it contains data from different services?  
\- Shared database is a [bad practice](https://learn.microsoft.com/en-us/azure/architecture/microservices/design/data-considerations) and it is not recommended to be used  
\- Breaking changes and versioning for data is not clear  
\- Single point of failure  
\- Difficult to measure SLO metrics  

### Option 3 - Use events to propogate image data to all services

We will use event-driven system where IMS will produce events when new image version is added and all other services will subscribe and listen events.
After receiving information about new image version, all dependent services will save it in their internal database and use later when necessary.
Every dependent service will have to implement logic to store images in internal database.

\+ No load on IMS service from API calls  
\+ High availability - every service store latest known images in internal database. If IMS is down, other services won't be impacted.  
\- Images data is duplicated in every dependent service (eventually, all dependent services will store all existing images)  
\- Using of images data is very complicated for other services. Every service needs to subscribe on events, listen them, save image data to internal database and manage / maintain information in own database.  

### Option 4 - Shared Redis Cache + fallback to API

We will have our own Redis instance which will be shared with all dependent services. Shared Redis instance will be fully owned by our team.  
IMS will use Redis to share the info which is required by other services (ImageReference, image size, etc).  
IMS will keep Redis data up-to-date and update when new images are released, latest is updated, etc.

We will provide shared Go module to work with images data:
- The module will retrieve data from Redis if Redis is available and data is available.
- The module will fallback to IMS API in case if Redis is down or data is not available.

All data contracts will be shared with shared module and owned by IMS team.  
Other services (LCM, GCAS, Runner config) will use shared module to access images data.

\+ The single datastore (source of truth) which is always up-to-date. No data duplicates.  
\+ Clear ownership - Shared Redis instance will only contain images data and will be fully owned by our team. So we don't depend on infrastructure which we don't own.  
\+ High availability - If IMS is down - Redis will still contain latest known data and other services will be able to use it. If Redis is down, the load on IMS API will be increased but no downtime and it should be fine as a short-term mitigation.  
\+ All images related stuff (service, shared module, infra) are located in the single repo and owned by our team.  
\+ If we need to change contract completely / make breaking changes - we can invalidate and regenerate Redis cache.  
\+ Easy to integrate SLO metrics / telemetry into shared module.  
\- We will need to maintain own Redis instance - it shouldn't be a big problem because we already have best practices, infra templates and shared modules for Redis in GPS / LCM services.  
\- We will need to implement and maintain shared module - Any other approach (API, Shared DB, Events) requires shared module too.  

## Decision

We had a long discussion within our team and with other teams (hosted-compute-4-9s, MMS, Larger Runners) in [Image Management service - Use API or Shared DB? #2](https://github.com/github/hosted-compute-ims/discussions/2) discussion.

We decided to proceed with "Option 4 - Shared Redis Cache + fallback to API" as the most perspective option with minimal number of drawbacks.  
The option 4 has very clear and simple design and satisfy all our requirements.