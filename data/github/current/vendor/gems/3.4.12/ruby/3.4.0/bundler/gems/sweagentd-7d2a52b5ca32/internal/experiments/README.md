# Experiments

The experiments Client provides a Feature Flag-like interface to interact with experiments using the [Experimentation Platform (ExP)](https://exp.microsoft.com/?workspaceId=dbd12384-5001-4e90-a863-526321eaf233).

```golang
// With the experimentClient already instantiated

featureName := "my-feature-name"
randomizationUnit := &experiments.TrafficFilter{
    Header: "X-Copilot-RandomizationUnit",
    Value: "SomeValue"
}

assignment := experimentClient.GetFeatureAssignment(ctx, featureName, randomizationUnit, nil)

if assignment.Variation == "my-variation" {
    // Experiment code goes here
} else {
    // Control code goes here
}

```

## Running and Toggling Experiments

Experiments and their associated FFs are managed in [ExP](https://exp.microsoft.com/a/search/experiments?workspaceId=dbd12384-5001-4e90-a863-526321eaf233) (requires VPN). To turn off an experiment, simply stop any active stages that are currently running.

Additional runbooks for experimentation can be found [here](https://github.com/github/copilot/tree/main/docs/online-experiments).

## The Experiment Client

The experiment client provides the means of interacting with ExP's Treatment Assignment Service (TAS) and provides a robust and configurable cache for storing experiment information.

```golang

experimentConfig := ExperimentConfig{
    Endpoint: "http://my.exp.tas.endpoint"
    ExtensionName: "my-copilot-feature",
    CacheConfig: experiments.NewDefaultCacheConfig(),
    DefaultFilterProps := &experiments.FilterProps{
        RepoName: "repoName",
        OrgID: "orgName",
        UserID: 1234567890
    } // Optional. Can be nil.
}

experimentClient := experiments.NewClient(ctx, logger, experimentConfig)
```

Under the hood, it calls the TAS with any [Traffic Filters](#traffic-filters) provided by the integrator. At least one traffic filter, the `randomizationUnit`, is required, as this is what the TAS uses to determine which value to return for a given experiment. The `randomizationUnit` for a given experiment is selected in ExP when the experiment is set up.

### GetFeatureAssignment

The GetFeatureAssignment method will return the feature assignment for a given feature name. 

```golang
assignment, found := experimentClient.GetFeatureAssignment(ctx, featureName, randomizationUnit, nil)
```

The Assignment struct is as follows:

```golang
type Assignment struct {
    Variation string
    AssignmentContext string
}
```

`Assignment.Variation` is intended to be used like a feature flag.
`Assignment.Context` is required to be sent with all telemetry associated with the variation for use in metric calculations.

Under the hood, this calls [GetAssignments](#getassignments) and either reads from the cache or hydrates the cache by calling the TAS.

## Traffic Filters

Traffic Filters are identifiers that are sent to ExP that we use to determine if the `randomizationUnit` is in the experiment. A common example of this is the `UserKind` traffic filter, which we use to "staff ship" an experiment.

```golang

trafficFilters := TrafficFilters{}

myTrafficFilter := &TrafficFilter{
    Header: "My-Traffic-Filter-Header",
    Value: "foo-value"
}

trafficFilters.Set(myTrafficFilter)

assignment := experimentClient.GetVariationAssignment(ctx, featureName, randomizationUnit, trafficFilters)

```

> [!NOTE]
> 
> Traffic Filter headers must be registered with ExP to be usable in an experiment. If new Traffic Filters are desired, reach out in the [#copilot-experimentation-enablement](https://github-grid.enterprise.slack.com/archives/C06N9TWQPSA).

### Traffic Filter Defaults

The headers provided in this package are [already registered with ExP](https://exp.microsoft.com/admin/ExperimentTrafficFilters/vscodeexpws?workspaceId=dbd12384-5001-4e90-a863-526321eaf233) and may be used without additional intervention. For convenience, there is a `NewTrafficFiltersDefaults` function for constructing trafficFilters:

```golang

defaultFilterProps := &FilterProps{
    RepoID: "1234567890",
    OrgID:  "1234567890",
    UserID: 1234567890
}

trafficFilters := NewTrafficFiltersDefaults(ctx, twirpClient, defaultFilterProps)

```

## The Assignments Cache

The assignments cache stores TAS call information keyed to randomization units and traffic filters. 

```golang
type CacheConfig struct {
    TTL time.Time // How long a cache entry is valid
    MaxSize int // The number of cache entries that will trigger a cleanup during each cleanup cycle
    CleanupInterval time.Time // The frequency at which the cleanup cycle runs
}
```

When a `NewAssignmentCache` is created, it will start a background worker that will run periodic cleanups of the cache based on the `CleanupInterval`. This removes expired cache entries and ensures the cache size doesn't run away, with an upper threshold limit set to the `MaxSize`.

A `NewDefaultCacheConfig()` function is included for convenience, creating a `CacheConfig` with the following values:

* TTL: 5 minutes
* MaxSize: 1000
* CleanupInterval: 1 min