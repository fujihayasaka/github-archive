package main

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/github/go-chatops/v2/security"
	"github.com/github/go-config/v2"
	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/pkg/rate"

	"github.com/github/launch/chatops"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/clients/launchtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/reqobs"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/abreaker"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/apphttp"
)

type application struct {
	cfg     Config
	closers []func() error
}

func newApplication() *application {
	return &application{}
}

func (a *application) ServiceName() string {
	return "launch-chatops"
}

// OnConfig runs before the mu service is started up.
func (a *application) OnConfig(_ *mu.Config) error {
	if err := launchconfig.LoadGlobalConfig(); err != nil {
		return err
	}

	return config.Load(&a.cfg)
}

// OnStartUp runs when the application is ready to start.
func (a *application) OnStartUp(svc *mu.Service) error {
	ctx := context.Background()
	log := svc.Config.NewLogger(a.cfg.CommonConfig.LoggerConfig)

	stats := svc.Config.NewStatter()
	stats.Start()

	obs := observability.New(log, stats)
	shutdown, err := tracing.Instrument(ctx, log, a.cfg.TracingEnabled)
	if err != nil {
		return err
	}
	a.closers = append(a.closers, func() error {
		shutdown()
		return nil
	})

	twirpTelemetry := reqobs.NewTwirpMetricsHooks(stats)
	twirpOpts := reqobs.AdaptTwirpHooksToClientOptions(twirpTelemetry, time.Now)

	deployerTwirpBreaker, err := abreaker.NewDeployerTwirpClientBreaker(ctx, obs, a.cfg.BreakerConfig)
	if err != nil {
		return err
	}

	defaultOpts := []apphttp.Option{apphttp.WithObservability(obs, a.cfg.RoundTripperConfig), apphttp.WithMaxTimeout(time.Second * 35)}

	twirpClient, err := launchtwirp.NewClient([]string{a.cfg.DeployerHMACSigningSecret}, deployerTwirpBreaker, stats, apphttp.NewClient(defaultOpts...))
	if err != nil {
		return err
	}

	deployerClient := deploy.NewLaunchDeploymentServiceProtobufClient(a.cfg.DeployerTwirpAddr, twirpClient, twirpOpts...)

	githubTwirpBreaker, err := abreaker.NewGithubTwirpClientBreaker(ctx, obs, a.cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "error creating ghtwirp circuit breaker")
	}

	ghTwirpClient, err := ghtwirp.NewClient(
		a.cfg.GitHubTwirpAddr,
		a.cfg.GitHubTwirpHMACSecret,
		obs,
		a.cfg.LaunchEnv,
		nil, // we want to avoid nil deref errors, but we also don't need a real cache for launch-chatops
		ahttp.NewRetryClient(
			githubTwirpBreaker,
			obs.Statter,
			//nolint:gocritic
			apphttp.NewClient(apphttp.WithObservability(obs, a.cfg.RoundTripperConfig)),
			"ghtwirp"),
		twirpOpts,
		launchconfig.IsMultiTenant(),
	)
	if err != nil {
		return errors.Wrap(err, "error creating GitHub Twirp client")
	}

	gidMigrator := deployer.NewGlobalIDMigrator(ghTwirpClient)

	validator, err := a.getRBACValidator()
	if err != nil {
		// TODO: Make this a startup error after validating it works
		obs.Error(ctx, "failed to setup ldap client", kvp.Err(err))
	}
	prompter, err := a.get2FAPrompter()
	if err != nil {
		// TODO: Make this a startup error after validating it works
		obs.Error(ctx, "failed to setup chatterbox client", kvp.Err(err))
	}

	configSyncService, err := a.getConfigSyncService(ctx, obs)
	if err != nil {
		return errors.Wrap(err, "cannot connect to redis")
	}

	app := chatops.NewApplication(log, deployerClient, gidMigrator, a.cfg.SecretsAppRelayID, validator, prompter, configSyncService)
	for _, chatop := range app.Chatops() {
		err := svc.RegisterChatopsCommand(chatop.Name, chatop.Help, chatop.Regexp, chatop.Handler)
		if err != nil {
			return err
		}
	}

	log.Debug(ctx, "launch-chatops registered",
		kvp.String("gh.launch.build_version", svc.Config.BuildVersion),
	)

	return nil
}

// OnShutdown runs when the application is ready to shut down.
// This is called after all request processing has finished.
func (a *application) OnShutdown(_ context.Context, _ *mu.Service) error { // nolint: unparam
	for _, closer := range a.closers {
		if err := closer(); err != nil {
			return fmt.Errorf("error invoking closer: %w", err)
		}
	}

	return nil
}

func (a *application) OnHealthCheck(_ *mu.Service) (string, map[string]any) {
	return "OK", map[string]any{}
}

func (a *application) getConfigSyncService(ctx context.Context, obs *observability.Observability) (rate.ConfigSyncService, error) {
	if a.cfg.RedisConfig.RedisURL == "" {
		return nil, nil
	}

	redisBreaker, err := abreaker.NewRedisBreaker(ctx, obs, a.cfg.BreakerConfig)
	if err != nil {
		return nil, err
	}

	redisClient, err := launchredis.New(ctx, a.cfg.RedisConfig, obs)
	if err != nil {
		return nil, err
	}

	configSyncService := rate.NewConfigSyncService(obs, redisClient, redisBreaker)
	return configSyncService, nil
}

func (a *application) getRBACValidator() (*security.Validator, error) {
	if a.cfg.LDAPConfigFile == "" || a.cfg.LDAPPassword == "" {
		// Avoid panic in security.LoadSecurityConfig during rollout
		return nil, fmt.Errorf("LDAP_CONFIG_FILE and/or LDAP_BINDPW is not provided. unable to make LDAP client")
	}

	securityConfig, err := security.LoadSecurityConfig(a.cfg.SecurityConfigFile)
	if err != nil {
		return nil, err
	}

	ldapClient, err := a.newLDAPClient()
	if err != nil {
		return nil, err
	}

	validator := &security.Validator{
		Auth:   a.newFidoClient(http.DefaultClient, a.cfg.FidoURL),
		Config: *securityConfig,
		LDAP:   ldapClient,
	}
	return validator, nil
}

func (a *application) newLDAPClient() (security.UserGroupsGetter, error) {
	return security.InitializeLDAPClient(a.cfg.LDAPConfigFile, a.cfg.LDAPPassword)
}

func (a *application) newFidoClient(httpClient *http.Client, fidoURL string) security.TwoFactorAuthorizer {
	return security.NewFidoAuthChallengerClient(httpClient, fidoURL)
}

func (a *application) get2FAPrompter() (security.Prompter, error) {
	return chatops.NewChatClient(
		a.cfg.ChatterboxURL,
		a.cfg.ChatterboxToken,
	)
}
