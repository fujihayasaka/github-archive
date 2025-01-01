// Package deployment contains configuration for deployment.
package deployment

// Config represents the configuration for deployment.
type Config struct {
	Environment string `config:"unknown,env=HEAVEN_DEPLOYED_ENV"`
	SHA         string `config:"unknown,env=HEAVEN_DEPLOYED_SHA"`
	Ref         string `config:"unknown,env=HEAVEN_DEPLOYED_REF"`
}
