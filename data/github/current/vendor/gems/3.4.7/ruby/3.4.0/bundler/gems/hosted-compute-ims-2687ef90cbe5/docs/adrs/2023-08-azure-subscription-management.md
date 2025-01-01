# Azure Subscription Management for IMS

## Context

### Purpose

The purpose of this document is to outline the approach for Azure subscriptions management in IMS (Image Management Service).  It will clarify the expected outcomes regarding gallery usage, space limitations, and how we plan to manage them.

A few items this document will focus on are:

- What Azure resources are required.
- Utilize multiple or single Azure subscriptions.
- What structure should be used to store the images.

### Subscriptions

One of the big questions we had as a part of the research was should Curated and Custom images be put in seperate subscriptions.  The answer to this question is yes. Due to the fact that the Custom images will be created by customers. This will give us more control and flexibility over the images.  We will be able to manage the images more effectively and efficiently for customers.  This will also allow us to have more control over the images and the subscriptions as far as cost and space.

![Alt text](/docs/assets/subscription.png)

### Subscription Resources

Outlined below is the resource configuration designated for implementation within the subscriptions. The subsequent resources are slated for utilization, with a detailed layout for Custom and Curated images. As you can see the resource are the same for both subscriptions.  The way they are utilized are a bit different based on the community.  

For both Custom and Curated Images, each image will be consolidated within a singular resource group. Nested within this structure, an Azure gallery will be generated for each customer or type of curated image. This gallery will serve as a repository for housing image definitions and their respective versions.

![Alt text](/docs/assets/resource-layout.png)

### Subscription Pools

A single subscription is designed to accommodate up to 100 users. By utilizing pools of subscriptions, we can expand the number of users beyond 100.

- All versions of an image will be stored in the same Azure gallery and definition.
- Image definitions for each user will be distributed across different subscriptions from a subscription pool, while one subscription will contain image definitions for multiple users.
- We will support up to 100 image versions for every image definition
- We will store 100 image definitions on every subscription (according to limit 10k of image versions per subscription)
This way, every user will be able to have indefinite number of image definitions and up to 100 image versions for every image definition

![Alt text](/docs/assets/subscription-pool.png)

### Avoiding Subscription Limitations

Please see the following limits, per subscription, for deploying resources using Azure Compute Galleries:

```markdown
- 100 galleries, per subscription, per region
- 1,000 image definitions, per subscription, per region
- 10,000 image versions, per subscription, per region
- 100 replicas per image version however 50 replicas should be sufficient for most use cases
```

Source: [Azure Compute Galleries](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/shared-image-galleries#limits)

We have identified the following items to help us avoid these limitations:

- Insights from Azure's documentation highlight crucial limitations that demand attention.
- An imperative strategy is required to effectively maneuver around these constraints.
- Our proposed solution involves the implementation of a backend scheduled task.
- This task will trigger at designated intervals and connect with the Azure subscription.
- It will diligently assess resource utilization in relation to defined limits.
- If the subscription nears these limits, a systematic process will be initiated to remove unused or outdated images.
- The task will also manage image version retention, preserving only the most recent N versions.
- The approach has a dual purpose: proactively avoiding limit breaches and maintaining operational efficiency.

### Subscription Pool Expansion

As the number of customers increases, we will need to expand the subscription pool.  This will allow us to continue to provide the same level of service to our customers.  

- We will need to create a job to provision new subscriptions.
- This job will also need to keep a pool of subscriptions ready for use.
- The job will need to be able to provision a new subscription when the pool is running low.

## Update on 29.10.2023

During implementation, we were faced with a couple of Azure limitations which we didn't initially consider in this ADR:
- Storage name and gallery name must be unique across the whole of Azure. So we need to generate a unique name for every subscription.
- Storage name, container name, gallery name and gallery image name have very strict limitations (these are described at the relevant points in code), therefore we can't use owner id and image name as part of our Azure resource names.

Our final solution still follows the most of proposals from this ADR. But the resource naming was reworked to satisfy Azure requirements.
Actual information about resources layout can be found in [Azure Resources Layout](../azure-resources-layout.md) document.
