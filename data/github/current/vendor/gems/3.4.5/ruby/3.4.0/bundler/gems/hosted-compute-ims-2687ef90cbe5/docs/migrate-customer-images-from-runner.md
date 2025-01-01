## Migrating Customer Images

Because this migrates all image definitions and image versions for each host. We'll migrate all hosts prior to moving to the next scale unit. So, unlike curated and marketplace, each step below should be done prior to moving to the next scale unit.

### Step 0 - Identify the hosts that need migrating

Something like this should work for getting the required host ids. Remember that proxima instances have proxima kusto clusters.

```
RunnerCustomImages()
| summarize count() by ScaleUnit, HostId
```

### Step 1 - Publish the image definitions and image versions for one host and ensure that it is successful.
If possible use one of the [L3 test hosts](https://dev.azure.com/mseng/_git/AzDevNext.Deploy?path=/runner-deploy.yml) to start since there should be one per scale unit. [Source for the cmdlet](https://github.com/github/actions-dotnet/blob/2f12a3407c0e4f024f005a55c05cfc5aca10891c/Runner/Tools/PowerShell/Cmdlets/PublishCustomerImagesToIms.cs).

> Publish-CustomerImagesToIms -HostId 'HostId'

Then verify that the job ran successfully and check related traces.

```
let tenant = 'runnerghubeus21';
let hostId = '';
JobHistory
| where PreciseTimeStamp > ago(1d)
| where Tenant == tenant or tenant == ''
| where JobSource == hostId or hostId == ''
| where Plugin == 'GitHub.Actions.Runner.Server.Jobs.PublishCustomerImagesToImsJob'
| project PreciseTimeStamp, Result, ResultMessage, E2EID

let tenant = 'runnerghubeus21';
let e2eId = '';
ProductTrace
| where PreciseTimeStamp > ago(1d)
| where Tenant == tenant or tenant == ''
| where E2EID == e2eId or e2eId == ''
| project PreciseTimeStamp, Tracepoint, Message, ExceptionType, E2EID
```

If there are problems, the job should be entirely rerunnable and we can requeue it from the same cmdlet.

### Step 2 - Migrate the same host and switch source of truth

For the same host, run the same cmdlet but with an additional switch to switch the source of truth at the end of rerunning the job.

> Publish-CustomerImagesToIms -HostId 'HostId' -MigrateToImsAsSourceOfTruth

Then verify the existing pools are working well and potentially rerun the L3 tests (a binary update also does this) against that L3 host.

### Step 3 - Publish the image definitions and versions for the remaining hosts on the scale unit 

Create a config change that calls this for each host that has customer images. At time of writing, there's currently 44 total hosts across all scale units that have customer images. So, it should be managable.

> Publish-CustomerImagesToIms -HostId 'HostId'

> ...

### Step 4 - Switch the source of truth for those hosts.

> Publish-CustomerImagesToIms -HostId 'HostId' -MigrateToImsAsSourceOfTruth

> ...

### Step 5 - Verify that all pools have been updated.

```
let scaleUnit = "";
RunnerPoolInfo
| where scaleUnit == "" or ScaleUnit == scaleUnit
| where ImageSource == "Custom"
| summarize arg_max(PreciseTimeStamp, *) by ServiceHost, PoolId
| where toint(ImageId) < 1000
| where PreciseTimeStamp > ago(3d)
```

If this returns any rows for the scale unit that's being migrated, redo step 4. This will also return hosts that started using custom images between steps 1 and 5, which is a helpful gate prior to step 6.

### Step 6 - Update the scale unit so that new hosts automatically have IMS as the source of truth for customer images.

Run a config change to set the following feature flag: `GitHub.Actions.Runner.Server.ImageManagementService.Customer.MigrationComplete`

Then repeat these steps on the next scale unit.
