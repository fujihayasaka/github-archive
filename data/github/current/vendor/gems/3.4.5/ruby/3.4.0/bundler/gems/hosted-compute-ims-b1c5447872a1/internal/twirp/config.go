package twirp

import (
	"time"
)

const (
	// Hmac verify keys are contained within a single string, delimited by spaces.
	// This allows us to support zero downtime rotation as the IMS service will loop through all keys when validating
	// a received HMAC header, ensuring at least one value matches, returning on the first successful match.
	HMAC_KEY_DELIMITER = " "
)

type Config struct {
	HTTPPort           int           `config:"21010,env=TWIRP_HTTP_PORT"`
	Timeout            time.Duration `config:"0s,env=TWIRP_HTTP_TIMEOUT"`
	HmacAuthEnabled    bool          `config:"true,env=HMAC_AUTH_ENABLED"`
	HmacAuthVerifyKeys []string      `config:",env=HOSTED_COMPUTE_IMS_HMAC_VERIFY_KEYS"`
	VssfAuthEnabled    bool          `config:"true,env=VSSF_AUTH_ENABLED"`
}
