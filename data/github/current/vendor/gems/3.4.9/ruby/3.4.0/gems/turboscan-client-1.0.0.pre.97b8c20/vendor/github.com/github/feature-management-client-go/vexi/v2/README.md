# 🚀 Vexi

Vexi for Go is a feature flag client created to enable feature management capabilities for internal GitHub applications written in Go. It handles all the complexities of syncing feature flag updates that are made inside the [Dev Portal](https://devportal.githubapp.com/feature-flags) and provides a simple interface for checking whether or not a feature is enabled.

**📚 For comprehensive API documentation, see the [API Reference Guide](./docs/api-reference.md).**

## Table of Contents

- [🔌 Adapters](#-adapters)
  - [Available Adapters](#available-adapters)
  - [Which Adapter Should I Use?](#which-adapter-should-i-use)
- [🛠️ Using Vexi for Go](#️-using-vexi-for-go)
  - [📦 Setup](#-setup)
  - [🎯 Making a feature flag check](#-making-a-feature-flag-check)
  - [👥 Making a feature flag check using actors](#-making-a-feature-flag-check-using-actors)
  - [🔧 Passing your own types as actors](#-passing-your-own-types-as-actors)
- [🧪 Unit Testing with Vexi for Go](#-unit-testing-with-vexi-for-go)
  - [📋 Setup of unit tests](#-setup-of-unit-tests)
  - [🎭 Fake adapter alternative for unit tests](#-fake-adapter-alternative-for-unit-tests)
- [💻 Codespace integration testing with Vexi for Go](#-codespace-integration-testing-with-vexi-for-go)
- [📊 Monitoring and Observability](#-monitoring-and-observability)
  - [Datadog Dashboard](#datadog-dashboard)
- [⚠️ Current limitations of Vexi for Go](#️-current-limitations-of-vexi-for-go)
- [❓ Questions and Answers](#-questions-and-answers)

## 🔌 Adapters

Adapters in the Vexi client are responsible for fetching feature flags and segments from various data sources. The Vexi library provides multiple built-in adapters and allows you to implement your own custom adapters.

### Available Adapters

Vexi provides several built-in adapters for different use cases:

| Adapter | Use Case | When to Use |
|---------|----------|-------------|
| **🌊 Hydro Adapter** | Production | Real-time feature flag streaming from Kafka. Recommended for most production scenarios. |
| **💾 Persistent Host Adapter** | Production (Host-based) | Enhanced Hydro adapter with file caching and environment overrides. Ideal for Capistrano deployments and persistent host environments. |
| **📡 Feature Flag Data Adapter** | Development/Testing | REST API adapter for Feature Management Lite service. Perfect for Codespaces and local development. |
| **🎭 Fake Adapter** | Integration Testing | Manually controllable adapter for testing. Allows you to set feature flag states programmatically. |

### Which Adapter Should I Use?

- **Production Applications**: Use **Hydro Adapter** for standard containerized deployments or **Persistent Host Adapter** for host-based deployments (Capistrano, etc.)
- **Development/Codespaces**: Use **Feature Flag Data Adapter** with Feature Management Lite
- **Integration Testing**: Use **Fake Adapter** for controlled testing scenarios
- **Unit Testing**: Generate mocks for the vexi public api interface for full control.

**📚 For detailed adapter configuration and advanced usage, see individual adapter documentation:**
- [Hydro Adapter](./docs/hydro-adapter.md)
- [Persistent Host Adapter](./docs/persistent-host-adapter.md)
- [Feature Flag Data Adapter](./docs/feature-flag-data-adapter.md)
- [File Adapter](./docs/file-adapter.md)
- [Fake Adapter](./docs/fake-adapter.md)

**🛠️ For implementing your own adapter, see the [Custom Adapters Guide](./docs/custom-adapters.md).**

## 🛠️ Using Vexi for Go

### 📦 Setup

1. **Add the latest release of Vexi to your repository.**

	```
	go get github.com/github/feature-management-client-go/vexi/v2
	```

2. **Configure a logger.** See [github-telemetry-go](https://github.com/github/github-telemetry-go) for more information. In this example, we refer to the configured logger as `logger`.
3. **Configure statsd.** See [go-stats](https://github.com/github/go-stats) for more information. In this example, we refer to the configured statsd client as `sc`.

	> [!WARNING]  
	> Do not use the inbuilt sampling on the go-stats client as that will suppress critical error metrics as well. Instead use the sampling option provided by Vexi for smart sampling.

4. **Configure OpenTelemetry (optional).** If you are using OpenTelemetry, you can also configure a tracer and pass it to the Vexi client. See the [Configuration Options](./docs/api-reference.md#configuration-options) section in the API Reference for more details.

5. **Import the Vexi and Vexi hydro adapters packages.**

	```golang
	import (
		"github.com/github/feature-management-client-go/vexi/v2"
		hydro_adapter "github.com/github/feature-management-client-go/vexi/v2/adapter/hydro"
	)
	```

	> **Note:** For more information on adapters, see individual adapter documentation linked above and the [Adapters](./docs/api-reference.md#adapters) section in the API Reference.

5. **Configure the hydro adapter.**

	You have three options for configuring the hydro adapter to select which feature flags your service subscribes to. The owning service is set on the feature flag in the devportal. Subscribing to multiple partitions increases the number of goroutines and startup time for the in-memory cache to be ready. All partitions should take about 5 seconds to process, whereas a single partition should be ready in 200-300ms.

	**Option 1: Single owning service** (recommended for optimal performance). Use this when your service only needs feature flags from one owning service.

	```golang
	hydroAdapter, err := hydro_adapter.NewAdapter(ctx,
		"YOURAPPNAME", // App name will be used to broadcast metrics and uniquely identify telemetry from the service.
		"YOURSERVICENAME", // Single owning service name
		hydro_adapter.WithLogger(logger),
		hydro_adapter.WithStatsClient(sc),
		hydro_adapter.WithHydroBrokers("BROKERLIST"),
		hydro_adapter.WithSystemRootCA(),
		hydro_adapter.WithCuratedSegments(), // Optional, enable curated segment support
	)
	if err != nil {
		panic(err)
	}
	```

	> **Note:** The owning service string MUST match the owning service value used for your feature flags in the devportal. These are the flags the hydro adapter will be providing to your service due to how it partitions hydro topics. If the owning service says `my-owning-service`, make sure you enter that exactly. In most cases this will be the same as your app name.

	**Option 2: Multiple owning services.** Use this when your service needs feature flags from multiple owning services. This requires more resources due to subscribing to multiple partitions.

	```golang
	owningServices := []string{"YOURSERVICENAME", "OTHERSERVICENAME", "YETANOTHERSERVICENAME"}
	hydroAdapter, err := hydro_adapter.NewAdapterWithOwningServices(ctx,
		"YOURAPPNAME",
		owningServices, // Multiple owning services
		hydro_adapter.WithLogger(logger),
		hydro_adapter.WithStatsClient(sc),
		hydro_adapter.WithHydroBrokers("BROKERLIST"),
		hydro_adapter.WithSystemRootCA(),
		hydro_adapter.WithCuratedSegments(), // Optional, enable curated segment support
	)
	if err != nil {
		panic(err)
	}
	```

	> **Note:** The values in the owning services array must exactly match the values used for feature flags in the devportal. By subscribing to more than one service, this will likely cause the adapter to subscribe to more hydro partitions, which may impact the performance of your service due to longer startup times and more resource usage, including memory and hydro connections. Only use this if you are sure you need it.

	**Option 3: All services** (use with caution). This subscribes to all feature flags from all services and should only be used for testing or when you need to subscribe to feature flags across all owning services.

	```golang
	hydroAdapter, err := hydro_adapter.NewAdapterWithAllServices(ctx,
		"YOURAPPNAME",
		hydro_adapter.WithLogger(logger),
		hydro_adapter.WithStatsClient(sc),
		hydro_adapter.WithHydroBrokers("BROKERLIST"),
		hydro_adapter.WithSystemRootCA(),
		hydro_adapter.WithCuratedSegments(), // Optional, enable curated segment support
	)
	if err != nil {
		panic(err)
	}
	```

The values for `BROKERLIST` come from the [hydro-client-go](https://thehub.github.com/epd/engineering/products-and-services/internal/hydro/installation/golang/) setup instructions. The `BROKERLIST` string is based on where you are running.
- For Dotcom environments (IAD), the kustomize string for the broker list looks like: `"hydro-kafka-potomac.service.ac4-iad.consul:9093,hydro-kafka-potomac.service.ash1-iad.consul:9093,hydro-kafka-potomac.service.va3-iad.consul:9093"` because we are using the potomac kafka cluster.
- For Proxima environments, the kustomize string for broker list looks like: `"hydro-kafka-%stamp%-%stamp%.service.%stamp%-az1.consul:9093,hydro-kafka-%stamp%-%stamp%.service.%stamp%-az2.consul:9093,hydro-kafka-%stamp%-%stamp%.service.%stamp%-az3.consul:9093"`
- The root CA is now configured by calling `WithSystemRootCA()`, which disables development mode and uses the System Root certificate store. A method called `WithRootCA()` is still available to specify which root certificate to use with the client, but this will not support certificate rotation without a deployment and is no longer recommended.

Enabling [Curated Segments](https://thehub.github.com/epd/engineering/products-and-services/internal/feature-flags/resources/curated-segments/) provides support for the use of a limited set of custom gates like staffship (`preview_features`), `microsoft_team_members` and [others](https://thehub.github.com/epd/engineering/products-and-services/internal/feature-flags/resources/curated-segments/#currently-available-curated-segments).

	> **💾 Alternative: Persistent Host Adapter**  
	> For persistent host environments (e.g., Capistrano deployments, Host Based deployments), consider using the [Persistent Host Adapter](./docs/persistent-host-adapter.md) instead of the standard hydro adapter. It provides file-based caching, environment variable overrides, and resilient startup behavior for production deployments where stability and uptime are critical. **Not recommended for containerized/Moda applications due to lack of persistent storage**.

6. **Start the hydro adapter.**

	**🚀 Recommended: Use `ResilientStart`** (preferred approach). With this approach, the hydro adapter will keep trying to start and fetch all feature flag data from Hydro until it succeeds or encounters a permanent error. When calling `ResilientStart`, you can choose to block (wait) for a certain amount of time for the cache to become ready, or make the call non-blocking. An error is returned only if a non-retryable error occurs during the blocking wait.

	> **Note:** When using `ResilientStart`, calls to `IsEnabled` or `IsEnabledWithError` may return a `ErrAdapterNotReady` error. To avoid handling this error, we recommend using the `IsEnabledWithDefaultValue` function, which will return the default value you specify for the feature flag if the cache is not yet ready.

	```golang
	err := hydroAdapter.ResilientStart(ctx, hydro_adapter.WithMaxBlockingWait(500*time.Millisecond), hydro_adapter.WithMaxBackoffWindow(5*time.Second))
	if err != nil {
		panic(err)
	}
	```

	`MaxBackoffWindow` is the maximum time the adapter will wait before attempting to retry after a failure. The retry window is randomized and this value is used as the ceiling. Defaults to 5 minutes.  
	`MaxBlockingWait` is the maximum time to wait for the adapter to be ready. If the wait time is exceeded before the adapter is ready, the adapter will continue and retry in the background until success or a non-retryable error is returned. Defaults to 5 seconds.

	> **Note:** `ResilientStart` is the recommended approach for most applications as it provides better resilience to transient network issues and Hydro availability problems.

	<details>
	<summary><strong>⚙️ Alternative: Use `Start` function (legacy approach)</strong></summary>

	Use the `Start` function of the hydro adapter and wait a reasonable amount of time. In this case, it will try to fetch all information about feature flags only once, and then you will receive the result through the channel.

	For timeout length, `Start` typically takes less than a second, so we think 5 seconds leaves sufficient buffer for anomalies. Keep in mind that this relies on the availability of [Hydro](https://thehub.github.com/epd/engineering/github-internal-platform/data-streaming/hydro/#availability), which has an SLO of 99.99%. In order to reduce the blast radius of potential availability incidents related to this upstream service, it is recommended that after the timeout has expired, services proceed in a degraded state where all enabled checks will return the default `false`.

	```golang
	cacheReady, err := hydroAdapter.Start(ctx)
	if err != nil {
		panic(err)
	}

	select {
	case <-cacheReady:
		// Cache is ready
	case <-time.After(5 * time.Second):
		// Timeout after 5 seconds
		log.LogError("starting in degraded state - vexi hydro cache was not ready in available timeout window.")
	}
	```

	> **Note:** Only use `Start` if your service or application requires all current (non-default) feature flag values to be available before execution, or you have implemented a custom fallback approach for feature flag values or Hydro unavailability.

	</details>

7. **Create the Vexi client using the Hydro adapter.**

	```golang
	vexiClient, err := vexi.NewVexiClient(ctx,
		hydroAdapter,
		"YOURAPPNAME",
		vexi.WithLogger(logger),
		vexi.WithStatsClient(sc),
		vexi.WithTracer(tracer), // Optional: Set a custom tracer if you need OpenTelemetry tracing
		vexi.WithSampling(vexi.SamplingRate10Percent), // Optional: Set sampling rate for feature flag check metrics
	)
	if err != nil {
		panic(err)
	}
	```

	> **Note:** The older `NewClient()` function is deprecated. Please use `NewVexiClient()`, which requires an application name parameter.

	> **📚 For detailed information about all client configuration options, see the [Configuration Options](./docs/api-reference.md#configuration-options) section in the API Reference.**

8. **Use the configured client.** The variable `vexiClient` from step 7 can now be used to perform feature flag checks in your service. The hydro adapter will cache updates to feature flags as they appear in the hydro topics.

### 🎯 Making a feature flag check

Once a feature flag client is configured, you can use it to check if feature flags are enabled. Remember to code your feature flag checks to "fail safe" either by handling errors or by choosing an appropriate default value that represents the safe state for your specific use case. > **📚 For comprehensive documentation on all feature flag checking methods, error handling, and examples, see the [Client](./docs/api-reference.md#client) and [Error Handling](./docs/api-reference.md#error-handling) sections in the API Reference.**

#### ✅ Quick Example: Check with default value

```golang
enabled := vexiClient.IsEnabledWithDefaultValue(ctx, "FeatureFlagName", false)
```

This method will return the specified default value (in this case `false`) if any errors occur during evaluation.

### 👥 Making a feature flag check using actors

To check if a feature flag is enabled for an actor, you need to construct a Vexi actor. Actors come in the form of `TYPE:Identifier`, for example a user might be `User:3434232` where `3434232` is the database ID used in that environment for the user. > **📚 For comprehensive documentation on actors, including all creation methods, extension helpers, and custom actor implementation, see the [Actors](./docs/api-reference.md#actors) section in the API Reference.**

#### Quick Example: Basic actor usage

```golang
// Basic actor creation
actor := vexi.NewActor(fmt.Sprintf("User:%d", myUserID))
enabled := vexiClient.IsEnabledWithDefaultValue(ctx, "FeatureFlagName", false, actor)

// Using extension helpers
import "github.com/github/feature-management-client-go/vexi/v2/extensions"

userActor := extensions.NewUser(myUserID)
orgActor := extensions.NewOrganization(myOrgID)
enabled := vexiClient.IsEnabledWithDefaultValue(ctx, "FeatureFlagName", false, userActor, orgActor)
```

### 🔧 Passing your own types as actors

You can pass your own custom types to the enabled check methods by implementing the `VexiActor` interface. This requires adding a `VexiID() string` method to your type that returns an actor string in the format `TYPE:VALUE`.

```golang
type MyObject struct {
	ID string
}

func (o *MyObject) VexiID() string {
	return fmt.Sprintf("MyObject:%s", o.ID)
}

myObj := &MyObject{ID: "13212312"}
enabled := vexiClient.IsEnabledWithDefaultValue(ctx, "FeatureFlagName", false, myObj)
```

## 🧪 Unit Testing with Vexi for Go

### 📋 Setup of unit tests

To unit test with Vexi for Go, you should use mocks. You will need to create an interface to be able to produce a mock that implements the `IsEnabledWithDefaultValue` method. With this in place, you can use expectations that the mock will return whatever you need from your feature flag client. The following is an example of what that interface would look like in your code.

```golang
type FeatureFlagClient interface {
   IsEnabledWithDefaultValue(ctx context.Context, featureFlagName string, defaultValue bool, actors ...vexi.Actor) bool
}
```

### 🎭 Fake adapter alternative for unit tests

In the event you don't have mocks set up or available, you can also use the `Fake` adapter when you configure the Vexi client for unit testing.

> **📚 For detailed information about the Fake adapter and other testing adapters, see the [Adapters](./docs/api-reference.md#adapters) section in the API Reference.**

```golang
import (
	"github.com/github/feature-management-client-go/vexi/v2"
	fake_adapter "github.com/github/feature-management-client-go/vexi/v2/adapter/fake"
)

// Create test adapter and client
testAdapter := fake_adapter.NewFakeAdapter(true) // Default return value
testVexiClient, err := vexi.NewVexiClient(ctx, testAdapter, "mock_app_name")

// Control feature flag state in tests
testAdapter.EnableFeatureFlag("my-feature")
testAdapter.AddActors("my-feature", []string{"User:123", "Organization:456"})
```

## 💻 Codespace integration testing with Vexi for Go

For development in Codespaces, Vexi can be used with the
[`fm-lite` codespace feature](https://github.com/github/features/tree/main/src/fm-lite). The `fm-lite` feature automatically installs the Feature Management Lite (FM-Lite) service and CLI in a Codespace. [Feature Management Lite](https://github.com/github/feature-management-lite) is a project that provides a standalone server that emulates the Feature Flag Data and Feature Flag Hub backend services and a CLI to create and modify feature flag state.

**To set up Feature Management Lite in a Codespace, perform the following steps:**

1. **Add the fm-lite (Feature Management Lite) codespace feature to devcontainer.json.**

	```json
	"customizations": {
		"codespaces": {
		"repositories": {
			"github/features": {
			"permissions": {
				"contents": "read",
				"packages": "read"
			}
			},
			"github/feature-management-lite": {
			"permissions": {
				"contents": "read",
				"packages": "read"
			}
			},
		}
		},
	},
	"features": {
		"ghcr.io/github/features/fm-lite:1": {},
	},
	```

   If your repository has Codespace prebuilds enabled, once the changes to devcontainer.json are merged, edit the repository's Codespaces prebuild settings and click update (no changes are required).
   This will trigger an updated permissions prompt that needs to be accepted.

2. **Configure Vexi to use the feature-flag-data adapter.** First import the Vexi and feature-flag-data adapter packages.

	```golang
	import (
		"github.com/github/feature-management-client-go/vexi/v2"
		ffd_adapter "github.com/github/feature-management-client-go/vexi/v2/adapter/feature_flag_data"
	)
	```

3. **Construct the feature-flag-data adapter and connect it to the running service** (feature-management-lite).

	```golang
	featureFlagDataAdapter, err := ffd_adapter.New(ffd_adapter.FeatureManagementLiteURL)
	if err != nil {
		panic(err)
	}

	vexiClient, err := vexi.NewVexiClient(ctx, featureFlagDataAdapter, "your_app_name", vexi.WithLogger(logger))
	if err != nil {
		panic(err)
	}
	```

	> **📚 For more information about the Feature Flag Data adapter, see the [Adapters](../docs/api-reference.md#adapters) section in the API Reference.**

4. **Using the feature-management-lite CLI,** you can change the state of feature flags in your codespace. For example, the following commands would create a feature flag and add actors on it.

	> **📚 For more information about the Feature Flag Data adapter, see the [Adapters](./docs/api-reference.md#adapters) section in the API Reference.**
	fm feature enable --create -n "MyFeatureFlag"
	fm feature actor add -n "MyFeatureFlag" -i "User:10000 User:10001 User:10002 User:10003 User:10004"

You can read more about the CLI once installed with `fm --help`.

## 📊 Monitoring and Observability

### Datadog Dashboard
Monitor your Vexi Go application metrics and performance using our dedicated Datadog dashboard:

🔗 **[Vexi Go App Metrics Dashboard](https://app.datadoghq.com/dashboard/2ga-u8h-uzu/vexi-go-app-metrics?fromUser=true&refresh_mode=sliding&from_ts=1749157716464&to_ts=1749762516464&live=true)**

## ⚠️ Current limitations of Vexi for Go

1. **[Custom gates](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/custom-gates/)** are mostly unsupported at this time. Monolith custom gates can be evaluated via an API, but this approach is not performant and generally not recommended. Vexi Go currently offers support for a limited subset of monolith custom gates via the [curated segments](https://thehub.github.com/epd/engineering/products-and-services/internal/feature-flags/resources/curated-segments/) feature. This feature comes with a small memory and performance cost and must be opted into by calling `WithCuratedSegments()` on the Vexi Hydro adapter during Vexi client configuration.

## ❓ Questions and Answers

1. **Q: How long does a change take to make it to my service when made in the devportal?**  
   **A:** Our goal is to have all changes reflected in 30 seconds or less. If they haven't arrived and the owning service name is correct, contact the feature-management team for help.
2. **Q: What do I do if I don't have an environment specific database ID for an actor?**  
   **A:** Since the devportal translates name to actors, you must have access to the ID. Or you need to create a custom actor that you use in the devportal and your code since Actor IDs can be any string.
3. **Q: Does Vexi for Go support dark shipping and percentage of actor checks?**  
   **A:** Yes.
4. **Q: If my feature flag isn't defined within the DevPortal, what will Vexi for Go return on any feature flag checks?**  
   **A:** It will return false.
5. **Q: If Vexi or its adapters are failing to operate, what will Vexi return?**  
   **A:** It will return false. Logs and stats telemetry can be used to diagnose the problem, and the feature management team can also help you.
6. **Q: Does Vexi memoize my request if I make the same request several times in the same thread of execution?**  
   **A:** No, it is up to you to memoize and cache responses from the Vexi client. Since the client is using in-memory caches, though, the lookups are super fast.
7. **Q: I've enabled or added actors to my feature flag and expect it to be enabled, but it doesn't appear to be. What's wrong?**  
   **A:** Verify that your Hydro adapter is configured to subscribe to the correct owning service. Each feature flag in the DevPortal has an owning service assigned to it, and your Hydro adapter must be configured to subscribe to that specific service. If you're using `NewAdapter` or `NewAdapterWithOwningServices`, check that the owning service names exactly match what's in the DevPortal. If your service needs feature flags from multiple owning services, make sure all required services are included in your adapter configuration.

Ask in the [Feature Management channel](https://app.slack.com/client/E01DLHH5JM6/C046568U26R) about any questions you have for Vexi for Go.
