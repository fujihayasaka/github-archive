package tokenauth

import (
	"strings"
	"time"
)

type Config struct {
	JWKSURL                     string        `config:",env=JWKS_URL"`
	JWKSRefreshInterval         time.Duration `config:"10m,env=JWKS_REFRESH_INTERVAL"`
	JWKSTimeout                 time.Duration `config:"10s,env=JWKS_TIMEOUT"`
	MultiTenantEnterpriseIssuer string        `config:",env=MULTI_TENANT_ENTERPRISE_ISSUER"`
}

func (cfg Config) JWKSURLs() []string {
	return strings.Split(cfg.JWKSURL, ",")
}
