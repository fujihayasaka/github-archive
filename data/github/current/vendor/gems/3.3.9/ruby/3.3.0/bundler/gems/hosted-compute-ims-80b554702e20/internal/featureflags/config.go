package featureflags

type Config struct {
	DotcomTwirpApiUrl    string `config:",env=DOTCOM_INTERNAL_TWIRP_URL"`
	DotcomTwirpApiHmac   string `config:",env=DOTCOM_INTERNAL_TWIRP_HMAC_KEY"`
	AllowFallbackToLocal bool   `config:"false,env=FEATURE_FLAGS_ALLOW_FALLBACK_TO_LOCAL"`
}
