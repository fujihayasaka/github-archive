IMS API calls sequence uses lazy logic to sync `ImageDefinitions` and `ImageVersions` between Azure and DB.
Below you can find 2 digrams describing logic behind DB-Azure sync for `Create` and `Delete` RCP calls.

## Create calls:

Diagram describes RPC calls to create image definitions and versions. 
RPC calls interact with the DB and the `PromotionJob` which is scheduled to for expensive operations that might need delayed retries. 
The `PromotionJob`, when called, creates or updates image versions in Azure based on whether an image definition already exists.

```mermaid
sequenceDiagram
  participant User
  participant API
  participant DB
  participant PromotionJob
  participant Azure

  User->>API: calls CreateImageDefinition API
  API->>DB: Creates image_definition
  Note over DB: Image definition in database, nothing in Azure yet
  API-->>User: response
 
  User->>API: calls CreateImageVersion API
  API->>DB: Creates image version
  API->>PromotionJob: Queues promotion job
  API-->>User: response

  PromotionJob->>Azure: Creates Azure image definition
  PromotionJob->>Azure: Creates Azure Image version

  User->>API: calls CreateImageVersion API (upload second version)
  API->>DB: Creates second image version
  API->>PromotionJob: Queues promotion job
  API-->>User: response

  Note over PromotionJob, Azure: Promotion job detects Azure image definition already exists
  PromotionJob->>Azure: Creates second Azure Image version
```


## Delete calls

Diagram describes RPC calls to delete image definitions and image versions. 
RPC calls interact with the DB and the `PromotionJob` which is scheduled to for expensive operations that might need delayed retries. 

When the final `DeleteImageVersion` RPC is called, the `DeleteImageVersionJob` ensures the Azure image definition is empty before deleting. 
When `DeleteImageDefinition` RPC is called, the database removes the image definition entry because the Azure image definition was removed in the previous step.


```mermaid
sequenceDiagram
    participant User
    participant API
    participant DB
    participant DeleteImageVersionJob
    participant Azure

    User->>API: DeleteImageVersion API
    API->>DB: mark image version as "Deleting"
    API->>DeleteImageVersionJob: enqueue DeleteImageVersionJob
    API-->>User: response
    DeleteImageVersionJob->>Azure: DeleteImageVersionJob deletes Azure image version
    Note over Azure: Keeps Azure image definition because there's another image version
    Azure->>DB: DeleteImageVersionJob removes image version from DB

    User->>API: DeleteImageVersion API (last image version)
    API->>DB: mark image version as "Deleting"
    API->>DeleteImageVersionJob: enqueue DeleteImageVersionJob
    API-->>User: response
    DeleteImageVersionJob->>Azure: DeleteImageVersionJob deletes Azure image version
    Note over Azure: Azure image definition has no image versions
    DeleteImageVersionJob->>Azure: DeleteImageVersionJob removes Azure image definition
    
    User->>API: DeleteImageDefinition API
    API->>DB: Remove image definition from DB
    Note over DB: Azure image definition was removed in previous step
    API-->>User: response
```
