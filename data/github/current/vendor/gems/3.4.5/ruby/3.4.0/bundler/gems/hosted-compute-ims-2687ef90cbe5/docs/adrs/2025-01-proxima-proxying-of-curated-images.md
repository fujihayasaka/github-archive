## Proxima Proxying of Curated Images

### Problem

IMS serves the following data:
- Curated Images
- Customer Images
- Marketplace Images (*maybe being these will become curated images effectively)

In Proxima stamps it's required that we enforce data resistance for customer data.

The current plan is for there to be an IMS instance in each Proxima stamp which handles `Customer Images`.

For `Curated Images` we call the Global IMS (dotcom/IAD) instance. 

This reduces the operational effort and COGs of owning `Curated Images` as we don't update and manage duplicates of the images in each stamp. They have no customer data so a single prepared and uploaded 
image can be used by all stamps.

When working on moving IMS to using Vexi we hit on an [issue with this approach](https://github.com/github/hosted-compute-ims/issues/926).

Vexi client improves the speed at which we can check flags and stores a local feature state cache for availability.

To effectively allow the Global IMS to check if a `Curated Image` is enabled for a Proxima stamp
it needs to query the feature flags of that stamp for the actor (say `General Motors` or say `gm/super-secret-project` repo).

The TWIRP based feature flag api and the new Vexi client both have issues with this:

1. Performance - Twirp calls are per flag check which is slow. Vexi must subscribe to Hydro queue per stamp which doesn't scale up to N future stamps.

2. Data Residency - Actor data is exposed at the Global IMS level which could be information about customer enterprise, org name, user or repo name ([Feature Management EDR](https://docs.google.com/document/d/1tB35tyLHh4s3DstFObuvgideyB-Lp8pVUQDmD1xouBM/edit?tab=t.0) which talks about Actor data residency). Even if we don't use customer identifyable information Vexi works by partitioning feature flag data into 20 partitions and the client pulls all data in that partition meaning we'd pull actor data for other applications in the stamp [🧵thread](https://github.slack.com/archives/C046568U26R/p1737384258225679?thread_ts=1734434761.707759&cid=C046568U26R).

3. The Twirp route will be deprecated/phased out in the future (maybe far future) leaving only Vexi.

The Global IMS approach also impacts availability, as Proxima is relying on the Global IMS instance, an issue with it could potentially degrade all stamps.

## Proposal

This should:
- fit the architecture of the new Vexi client
- ensure tenant data residency
- isolate stamps from Global IMS instance failures

We would expand the usage of the in-stamp IMS instance, it would handle proxying and caching the upstream 
curated images data from the Global IMS instance.

Feature flag evaluation would be done in-stamp, this would allow usage of Vexi client by fitting its design
and ensure actor information didn't leak to the Global IMS instance from the stamp.

On the Global IMS instance we would implement an endpoint which exposed the unfiltered list (without applying flags) of available curated images.

In the Proxima IMS instance a background go routine would pull this information and store it in its MySQL database. It **would not** use the existing `image_definition`, `image_version` tables as both Proxima and Global IMS have auto incrementing IDs so there would be overlap between the IDs. The cached information would be stored in a separate table, for example a serialized JSON blob or JSON column with key. 

When a customer requested a list of Curated Images in their stamp the Proxima IMS would retrieve the unfiltered list of Curated Images from its database then filter them using the Proxima Actor via Vexi.

The following calls would be Proxied back to Global IMS by the Proxima IMS:


- `ImagesAPI.ListCuratedImageDefinitions`
- `ImagesAPI.GetCuratedImageDefinition`
- `ImagesAPI.ListCuratedImageVersions`
- `ImagesAPI.GetCuratedImageVersion`
- `InternalAPI.GetImageReference` (if image_source == "Curated")
- `InternalAPI.GetImageDetails` (if image_source == "Curated")

#### Upstream Global IMS endpoint used by downstream IMS Proxy

This will be the endpoint that Proxima IMS uses to populate its DB cache for the curated images.

##### Option 1: We cache raw DB data

Potentially we will need to cache the content of image_definition table (only curated image definitions), image_version table (associated image versions) and azure_subscription.
The amount of data is relatively small: 20 curated images (~50 in worst case in future) x 30 image versions + 3 azure subscriptions. But the structure of data looks a bit complex.

##### Option 2: We build a model based and return this via a new API call on Global IMS

We can cache some interim structure (almost ready response, the only need to resolve FF).

Not sure what approach will be more flexible on long term.

Also, right now, we have the following API calls:

- `AdminAPI.ListCuratedImageDefinitions` -> this method is intended to be called from stafftools and it returns almost raw image information (unresolved FF, etc) but without additional metadata (image size, total image version size, latest image version, etc) because metadata is only required in customers' UI.
- `ImagesAPI.ListCuratedImageDefinitions` -> this method is intended to be called from dotcom UI and it returns already resolved FF (in context of current user) and additional metadata fields
- `InternalAPI.GetImageReference` -> this method returns `ImageReference` of specific image version.

So, potentially, Proxima IMS can retrieve all necessary information using combination of calls above. But it will be very inefficient because Proxima IMS will need to make `1 AdminAPI.ListCuratedImageDefinitions` + `1 ImagesAPI.ListCuratedImageDefinitions` + `N AdminAPI.ListCuratedImageVersions` + `NxM InternalAPI.GetImageReference` API calls.

The one suggestion from @maxim-lobanov:


- Extend `AdminAPI.ListCuratedImageDefinitions` to include information from `ImagesAPI.ListCuratedImageDefinitions` and `InternalAPI.GetImageReference`
- Use `AdminAPI.ListCuratedImageDefinitionsResponse` as an interim structure to cache
- Then we only need to maintain mapping from `AdminAPI.ListCuratedImageDefinitionsResponse` to `ImagesAPI.ListCuratedImageDefinitions` with resolving FFs

`AdminAPI` is only called from stafftools. So, it shouldn't be a problem to add additional fields to this API. No performance concerns here.
Actually, I already considered integrating `InternalAPI.GetImageReference` to `AdminAPI.ListCuratedImageDefinitions` because right now our stafftools UI has to perform multiple calls.

This approach creates dependency between `AdminAPI.ListCuratedImageDefinitions` and `ImagesAPI.ListCuratedImageDefinitions`. Any new fields in `ImagesAPI` must be added to `AdminAPI` too but I think it should be fine.



##### Suggestion

Go with option 2 having an interim model and endpoint. 

This allows us to change the DB structure and map to the model required. Otherwise a change to db in Global IMS could cause impact to Proxima IMS if not rolled out simultaniously. 

It's a little more work but I think the flexibility will be useful longer term.


### Benefits

1. Services in Proxima have one IMS endpoint to call and don't have to be aware of both Proxima and Global IMS instances and when to use each.
1. Align with design of Feature Flag system for Proxima allowing performant use of Vexi
2. Ensure actor information doesn't breach tenant data isolation as stays in stamp
3. Isolation of Proxima from Global IMS improves availability of tenants. During an outage of Global IMS they continue to be fully functional
4. Performance, serving data stored in MySQL instance in Australia directly in Australia rather than requiring a hop back to IAD Datacenters (P95 of [823ms](https://app.datadoghq.com/s/59fe6c40c/57f-3yn-agb) form Heaven to Australia Kube Cluster API)

### Downsides

1. Sync process needs monitoring. Potential for Proxima stamps to hold out of data information.
2. Database configuration and added state for the IMS Proxima instances to handle.
3. Authentication from Proxima IMS to Global IMS configuration (probably needed anyway for stamp to talk to global instance)

## Staged Rollout

To address the interim performance issues with IMS curated image calls we can take an interim step.

Within the Global IMS we will use the Vexi Client when the originating call is from the `dotcom` stamp.

If the call originates in a Proxima stamp we'll fallback to using the `twirp` Features API call.

This will improve performance for the dotcom pages impacted. 

Stage two would be to implement the proxy and cache in proxima IMS instances, at which point we could
remove the twirp calls.

## Conclusions

TBD
