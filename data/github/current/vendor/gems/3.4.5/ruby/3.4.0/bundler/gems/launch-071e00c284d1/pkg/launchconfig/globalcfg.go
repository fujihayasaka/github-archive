// This file contains configuration you can check anywhere in the code after LoadCommonConfig() has been called.
// Best practice: Export derived configuration (e.g. UsingNextGIDs()) rather than deployment type directly.
package launchconfig

import (
	"os"
	"strings"
	"time"

	"github.com/github/go-config/v2"
	"github.com/pkg/errors"
)

var cfg *CommonConfig

// LoadGlobalConfig loads the global configuration from the environment
// This should be called on service startup.
func LoadGlobalConfig() error {
	var c CommonConfig
	if err := config.Load(&c); err != nil {
		return err
	}

	cfg = &c

	// cfg.StatsAddr is required setting for hosted deployment processes
	if cfg.StatsAddr == "" && !UseNullStatter() {
		return errors.New("STATS_ADDR must be set")
	}

	return nil
}

func UsingNextGIDs() bool {
	// we're using next global ids if we're not running on Enterprise
	loadConfigIfNecessary()

	return !cfg.IsEnterprise()
}

func UsingRunnerService() bool {
	// we're using Runner service if we're not running on Enterprise
	loadConfigIfNecessary()

	return !cfg.IsEnterprise()
}

func UsingResultsService() bool {
	// skip results service on GHES
	loadConfigIfNecessary()

	return !cfg.IsEnterprise()
}

func UseNullStatter() bool {
	loadConfigIfNecessary()

	if cfg.Environment() == TestAppEnv {
		return true
	}

	// https://github.com/github/c2c-actions-experience/issues/2982#issuecomment-661206260
	if cfg.IsEnterprise() {
		return true
	}

	return false
}

func Environment() AppEnv {
	loadConfigIfNecessary()
	return cfg.Environment()
}

func StatsPrefix() string {
	loadConfigIfNecessary()
	return cfg.StatsPrefix
}

func StatsAddr() string {
	loadConfigIfNecessary()
	return cfg.StatsAddr
}

func StatsPeriod() time.Duration {
	loadConfigIfNecessary()
	return cfg.StatsPeriod
}

func EmitQueueRunEvent() bool {
	loadConfigIfNecessary()
	// no consumers on Enterprise, yet
	return !cfg.IsEnterprise()
}

func EmitWorkflowCancelRequestEvent() bool {
	loadConfigIfNecessary()
	// no consumers on Enterprise, yet
	return !cfg.IsEnterprise()
}

func EmitWorkflowUpdateEvent() bool {
	loadConfigIfNecessary()
	// no consumers on Enterprise, yet
	return !cfg.IsEnterprise()
}

func FourNinesAvailable(allowMultiTenant bool) bool {
	loadConfigIfNecessary()
	// No 4nines infra for enterprise and no 4nines for multi tenant unless actions_enable_run_service_proxima is enabled
	if allowMultiTenant {
		return !cfg.IsEnterprise()
	}
	return !cfg.IsEnterprise() && !IsMultiTenant()
}

func IsMultiTenant() bool {
	loadConfigIfNecessary()
	return cfg.IsMultiTenant
}

func IsLab() bool {
	loadConfigIfNecessary()
	return cfg.IsLab()
}

func IsDotcom() bool {
	loadConfigIfNecessary()
	return !cfg.IsEnterprise() && !cfg.IsMultiTenant
}

func IsDevelopment() bool {
	loadConfigIfNecessary()
	return cfg.IsDevelopment()
}

func UsingResults() bool {
	loadConfigIfNecessary()
	return !cfg.IsEnterprise() && !cfg.IsMultiTenant
}

func UsingPayloadsBlobStorage() bool {
	loadConfigIfNecessary()
	return !cfg.IsEnterprise()
}

func UseAqueductJobTTL() bool {
	loadConfigIfNecessary()
	return !cfg.IsEnterprise()
}

// EnvironmentTag returns the metrics tag for the current environment
func EnvironmentTag() string {
	loadConfigIfNecessary()

	return cfg.Environment().String()
}

// loadConfigIfNecessary is primarily intended for tests. See LoadCommonConfig.
func loadConfigIfNecessary() {
	// last writer wins
	if cfg == nil {
		if runningUnderTest() && os.Getenv("LAUNCH_ENV") == "" {
			os.Setenv("LAUNCH_ENV", TestAppEnv.String())
		}

		if err := LoadGlobalConfig(); err != nil {
			err = errors.Wrap(err, "config not initialized. failed to load common config just-in-time")
			panic(err)
		}
	}
}

func runningUnderTest() bool {
	return strings.HasSuffix(os.Args[0], ".test")
}

// ResetConfig is intended to reset the global config for tests.
func ResetConfig() {
	cfg = nil
}
