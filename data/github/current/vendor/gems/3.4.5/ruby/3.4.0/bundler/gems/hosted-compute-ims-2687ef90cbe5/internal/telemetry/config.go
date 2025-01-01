package telemetry

import (
	"time"
)

type Config struct {
	// General configuration values
	ServiceName string `config:"hosted-compute-ims,env=SERVICE_NAME"`
	Env         string `config:"development,env=ENVIRONMENT"`
	DeployedSha string `config:"unknown,env=HEAVEN_DEPLOYED_SHA"`
	DeployedRef string `config:"unknown,env=HEAVEN_DEPLOYED_REF"`
	StampName   string `config:"unknown,env=GH_OTEL_STAMP"`
	// Datadog configuration values
	StatsAddr     string        `config:",env=STATS_ADDR"`
	StatsPort     string        `config:"28125,env=STATS_PORT"`
	StatsInterval time.Duration `config:"5s,env=STATS_INTERVAL"`
	StatsPrefix   string        `config:"hosted_compute_ims,env=STATS_PREFIX"`
	// Sentry configuration values
	FailbotURL string `config:",env=FAILBOT_HAYSTACK_URL"`
	// Kubernetes specific env vars
	KubernetesPod       string `config:",env=KUBE_POD"`
	KubernetesNamespace string `config:",env=KUBE_NAMESPACE"`
	KubernetesNode      string `config:",env=KUBE_NODE_HOSTNAME"`
}

func (c *Config) IsProductionEnv() bool {
	return c.Env != "development"
}
