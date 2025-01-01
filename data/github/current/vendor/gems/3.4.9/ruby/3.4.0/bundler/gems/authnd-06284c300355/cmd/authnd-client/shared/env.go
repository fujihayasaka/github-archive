package shared

import (
	"github.com/github/authnd/internal/common"
)

var envNameMap = map[string]string{
	"dev":  "development",
	"prod": "production",
}

type EnvConfig struct {
	Name          string
	KafkaBroker   string
	AuthndBaseUrl string
	EncryptionKey string
	IsDevelopment bool
}

var envConfigMap = map[string]EnvConfig{
	"development": {
		Name:          "development",
		KafkaBroker:   "127.0.0.1:9092",
		AuthndBaseUrl: "http://localhost:8000",
		EncryptionKey: common.DevelopmentEncryptionKey,
		IsDevelopment: true,
	},
	"enterprise": {
		Name:          "enterprise",
		KafkaBroker:   "127.0.0.1:9093",
		AuthndBaseUrl: "http://127.0.0.1:4672",
	},
	"canary": {
		Name:          "canary",
		KafkaBroker:   "hydro-kafka-yukon-boot-1.service.iad.github.net:9093",
		AuthndBaseUrl: "https://authnd-production-canary.service.iad.github.net",
	},
	"production": {
		Name:          "production",
		KafkaBroker:   "hydro-kafka-yukon-boot-1.service.iad.github.net:9093",
		AuthndBaseUrl: "https://authnd-production.service.iad.github.net",
	},
}

func GetEnvConfig(envName string) (EnvConfig, bool) {
	if envName == "" {
		return envConfigMap["development"], true
	}

	if resolvedName, ok := envNameMap[envName]; ok {
		envName = resolvedName
	}
	if config, ok := envConfigMap[envName]; ok {
		return config, true
	}
	return EnvConfig{}, false
}
