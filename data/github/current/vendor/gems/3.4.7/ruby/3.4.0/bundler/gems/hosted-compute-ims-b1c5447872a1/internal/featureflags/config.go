package featureflags

import "strings"

type Config struct {
	DotcomTwirpApiUrl    string   `config:",env=DOTCOM_INTERNAL_TWIRP_URL"`
	DotcomTwirpApiHmac   string   `config:",env=DOTCOM_INTERNAL_TWIRP_HMAC_KEY"`
	SupportedStamps      []string `config:"dotcom,env=FEATURE_FLAGS_SUPPORTED_STAMPS"`
	AllowFallbackToLocal bool     `config:"false,env=FEATURE_FLAGS_ALLOW_FALLBACK_TO_LOCAL"`
}

func (c *Config) GetTwirpApiUrlForStamp(stamp string) string {
	if stamp == "dotcom" {
		stamp = "iad"
	}

	return strings.Replace(c.DotcomTwirpApiUrl, "{{stamp}}", stamp, 1)
}
