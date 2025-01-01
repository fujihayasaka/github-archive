package featureflags

import (
	"strings"
)

type Config struct {
	DotcomTwirpApiUrl       string   `config:",env=DOTCOM_INTERNAL_TWIRP_URL"`
	DotcomTwirpApiHmac      string   `config:",env=DOTCOM_INTERNAL_TWIRP_HMAC_KEY"`
	SupportedStamps         []string `config:"dotcom,env=FEATURE_FLAGS_SUPPORTED_STAMPS"`
	AllowFallbackToLocal    bool     `config:"false,env=FEATURE_FLAGS_ALLOW_FALLBACK_TO_LOCAL"`
	VexiHydroBrokers        string   `config:",env=VEXI_HYDRO_BROKERS"`
	VexiHydroRootCA         string   `config:",env=VEXI_HYDRO_ROOT_CA"`
	VexiHydroInitTimeoutSec float32  `config:"15,env=VEXI_HYDRO_INIT_TIMEOUT_SEC"`
	VexiFFLiteUrl           string   `config:",env=VEXI_FF_LITE_URL"`
}

func (c *Config) HasLocalFFLite() bool {
	return c.VexiFFLiteUrl != ""
}

func (c *Config) GetTwirpApiUrlForStamp(stamp string) string {
	if stamp == "dotcom" {
		stamp = "iad"
	}

	return strings.Replace(c.DotcomTwirpApiUrl, "{{stamp}}", stamp, 1)
}
