package abreaker

import "time"

// Config represents the circuit breaker configurations for
// all of Launch. It's possible to override these defaults by setting
// appropriate environment variables in the launch services' process.
//
// See the go-config documentation for the default naming convention
// that will map a tagged filed to an environment variable. Check other
// configuration in Launch for examples, most choose to override the default.
//
// If you're interested in adding a new breaker, see the package documentation.
type Config struct {
	// Defaults
	DefaultBreakerWindowSize    int           `config:"10"`
	AzpDefaultBreakerWindowSize int           `config:"30"`
	DefaultInitialBackoff       time.Duration `config:"500ms"`

	// GitHubClient
	GitHubClientBreakerName string  `config:"github_client"`
	GitHubClientBreakerRate float64 `config:"0.9"`
	GitHubClientBreakerMin  int64   `config:"100"`

	// 	GitHubTwirpClient
	GitHubTwirpClientBreakerName string  `config:"github_twirp_client"`
	GitHubTwirpClientBreakerRate float64 `config:"0.9"`
	GitHubTwirpClientBreakerMin  int64   `config:"20"`

	// GitHubTwirpBillingClient
	GitHubTwirpBillingClientBreakerName    string        `config:"github_twirp_billing_client"`
	GitHubTwirpBillingClientBreakerRate    float64       `config:"0.2"`
	GitHubTwirpBillingClientBreakerMin     int64         `config:"20"`
	GitHubTwirpBillingClientWindowSize     int           `config:"30"`
	GitHubTwirpBillingClientInitialBackoff time.Duration `config:"2s"`

	// AzpRepoClient
	AzpRepoClientBreakerName string  `config:"azp_repo_client"`
	AzpRepoClientBreakerRate float64 `config:"0.9"`
	AzpRepoClientBreakerMin  int64   `config:"60"`

	// AzpJobCLIClient
	AzpJobCLIClientBreakerName string  `config:"job_cli_azp_client"`
	AzpJobCLIClientBreakerRate float64 `config:"0.9"`
	AzpJobCLIClientBreakerMin  int64   `config:"1000"`

	// AzpBearerToken
	AzpBearerTokenBreakerName string  `config:"azp_bearer_token"`
	AzpBearerTokenBreakerRate float64 `config:"0.9"`
	AzpBearerTokenBreakerMin  int64   `config:"20"`

	// AzpKeyVault
	AzpKeyVaultBreakerName string  `config:"azp_key_vault"`
	AzpKeyVaultBreakerRate float64 `config:"0.9"`
	AzpKeyVaultBreakerMin  int64   `config:"5"`

	// AzpS2S
	AzpS2SBreakerName      string `config:"azp_s2s"`
	AzpS2SBreakerThreshold int64  `config:"15"`

	// Redis
	RedisBreakerName string  `config:"redis"`
	RedisBreakerRate float64 `config:"0.3"`
	RedisBreakerMin  int64   `config:"30"`

	// RedisReceiver
	RedisReceiverBreakerName string  `config:"redis_receiver"`
	RedisReceiverBreakerRate float64 `config:"0.3"`
	RedisReceiverBreakerMin  int64   `config:"15"`

	// AqueductDeployerClient
	AqueductDeployerClientBreakerName string  `config:"aqueduct_deployer_client"`
	AqueductDeployerClientBreakerRate float64 `config:"0.9"`
	AqueductDeployerClientBreakerMin  int64   `config:"20"`

	// AqueductWorkerClient
	AqueductWorkerClientBreakerName string  `config:"aqueduct_worker_client"`
	AqueductWorkerClientBreakerRate float64 `config:"0.9"`
	AqueductWorkerClientBreakerMin  int64   `config:"200"`

	// SpokesdClient
	SpokesdClientBreakerName string  `config:"spokesd_client"`
	SpokesdClientBreakerRate float64 `config:"0.9"`
	SpokesdClientBreakerMin  int64   `config:"20"`

	// AuthzdClient
	AuthzdClientBreakerName      string `config:"authzd_client"`
	AuthzdClientBreakerThreshold int64  `config:"5"`

	// DeployerTwirpClient
	DeployerTwirpClientBreakerName string  `config:"deployer_twirp_client"`
	DeployerTwirpClientBreakerRate float64 `config:"0.9"`
	DeployerTwirpClientBreakerMin  int64   `config:"25"`

	// TokenServiceClient
	JobCLITokenServiceBreakerName            string `config:"job_cli_token_service"`
	JobCLITokenServiceClientBreakerThreshold int64  `config:"10"`

	// FrenoClient
	FrenoClientBreakerName string  `config:"freno_client"`
	FrenoClientBreakerRate float64 `config:"0.9"`
	FrenoClientBreakerMin  int64   `config:"10"`

	// LaunchDBClient
	LaunchDBClientBreakerName      string `config:"launch_db"`
	LaunchDBClientBreakerThreshold int64  `config:"500"`

	// LaunchRODBClient
	LaunchRODBClientBreakerName      string `config:"launch_ro_db"`
	LaunchRODBClientBreakerThreshold int64  `config:"500"`

	// PayloadsClient
	PayloadsClientBreakerName      string `config:"payloads_db"`
	PayloadsClientBreakerThreshold int64  `config:"500"`

	// KredzTwirpClient
	KredzTwirpClientBreakerName string  `config:"kredz_twirp_client"`
	KredzTwirpClientBreakerRate float64 `config:"0.9"`
	KredzTwirpClientBreakerMin  int64   `config:"25"`

	// VarzTwirpClient
	VarzTwirpClientBreakerName string  `config:"varz_twirp_client"`
	VarzTwirpClientBreakerRate float64 `config:"0.9"`
	VarzTwirpClientBreakerMin  int64   `config:"25"`

	// TransitionClient
	TransitionClientBreakerName      string `config:"transition_unique_client"`
	TransitionClientBreakerThreshold int64  `config:"10"`

	// ResultsTwirpClient
	ResultsTwirpClientBreakerName string  `config:"results_twirp_client"`
	ResultsTwirpClientBreakerRate float64 `config:"0.9"`
	ResultsTwirpClientBreakerMin  int64   `config:"100"`

	// RunServiceTwirpClient
	RunServiceTwirpClientBreakerName string  `config:"run_service_twirp_client"`
	RunServiceTwirpClientBreakerRate float64 `config:"0.9"`
	RunServiceTwirpClientBreakerMin  int64   `config:"100"`

	// BillingPlatformTwirpClient
	BillingPlatformTwirpClientBreakerName    string        `config:"billing_platform_twirp_client"`
	BillingPlatformTwirpClientBreakerRate    float64       `config:"0.2"`
	BillingPlatformTwirpClientBreakerMin     int64         `config:"20"`
	BillingPlatformTwirpClientWindowSize     int           `config:"30"`
	BillingPlatformTwirpClientInitialBackoff time.Duration `config:"2s"`

	// NetworkServiceClient
	NetworkServiceClientBreakerName    string        `config:"network_service_client"`
	NetworkServiceClientBreakerRate    float64       `config:"0.2"`
	NetworkServiceClientBreakerMin     int64         `config:"20"`
	NetworkServiceClientWindowSize     int           `config:"30"`
	NetworkServiceClientInitialBackoff time.Duration `config:"2s"`
}
