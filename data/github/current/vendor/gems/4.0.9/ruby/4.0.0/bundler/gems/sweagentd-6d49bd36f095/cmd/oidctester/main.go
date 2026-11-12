// Package main provides a small testing CLI that reads a settings.json configuration
// file and performs the full OIDC token exchange flow using local signing,
// printing the resulting tokens as JSON to stdout.
//
// Usage:
//
//	oidctester -config settings.json -actor-id 123 -actor octocat \
//	  -owner-id 456 -owner github -repo-id 789 -repo github/sweagentd \
//	  -app-id 12345 -app-client-id Iv1.abc123
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"time"

	"github.com/github/sweagentd/internal/auth/oidc"
	"github.com/github/sweagentd/internal/auth/oidc/authndsigner"
	"github.com/github/sweagentd/internal/auth/oidc/devsigner"
	"github.com/github/sweagentd/internal/auth/oidc/devsigner/signerhttp"
	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
)

var (
	flagConfigPath        = flag.String("config", "testdata/copilot/settings.json", "path to settings.json config file with OIDC configuration")
	flagActorID           = flag.Int64("actor-id", 1, "GitHub user ID")
	flagActorLogin        = flag.String("actor-login", "monalisa", "GitHub user login")
	flagActorType         = flag.String("actor-type", "user", "actor type (user, org)")
	flagOwnerID           = flag.Int64("owner-id", 4, "GitHub owner (org/user) ID")
	flagOwner             = flag.String("owner", "github", "GitHub owner (org/user) name")
	flagOwnerIsOrg        = flag.Bool("owner-is-org", false, "whether the repository owner is an organization")
	flagRepoID            = flag.Int64("repo-id", 6, "GitHub repository ID")
	flagRepo              = flag.String("repo", "private-server", "GitHub repository full name (owner/repo)")
	flagAppID             = flag.Int64("app-id", 0, "GitHub App ID")
	flagAppClientID       = flag.String("app-client-id", "Iv23ctzlsVrAf9UtZ48B", "OAuth client ID for the GitHub App")
	flagAppInstallationID = flag.Int64("app-installation-id", 0, "installation ID for the GitHub App")
)

func main() {
	flag.Parse()

	err := mainWithLogging()
	if err != nil {
		fmt.Println("failed to run oidctester:", err)
		os.Exit(1)
	}
}

func mainWithLogging() error {
	cfg, err := config.Load()
	if err != nil {
		return goerrors.Errorf("failed to load config: %w", err)
	}

	obsv, err := cfg.NewObservabilityExporters("oidctester")
	if err != nil {
		return goerrors.Errorf("failed to create observability exporters: %w", err)
	}

	return realMain(cfg, obsv)
}

type tokenOutput struct {
	SecretName  string `json:"secret_name"`
	IDToken     string `json:"github_id_token"`
	AccessToken string `json:"integrator_access_token"` //nolint:gosec // This is the expected output of the CLI
}

// routeAdapter adapts http.ServeMux to the interface expected by signerhttp.Handler.RegisterRoutes.
type routeAdapter struct {
	mux *http.ServeMux
}

func (r routeAdapter) Get(pattern string, handler http.HandlerFunc) {
	r.mux.HandleFunc("GET "+pattern, handler)
}

func realMain(cfg *config.Config, obsv observability.Exporters) error {
	configPath := *flagConfigPath
	actorID := *flagActorID
	actorLogin := *flagActorLogin
	actorType := jobs.ActorType(*flagActorType)
	ownerID := *flagOwnerID
	owner := *flagOwner
	ownerIsOrg := *flagOwnerIsOrg
	repoID := *flagRepoID
	repo := *flagRepo
	appID := *flagAppID
	appClientID := *flagAppClientID
	appInstallationID := *flagAppInstallationID

	data, err := os.ReadFile(configPath)
	if err != nil {
		return goerrors.Errorf("failed to read config file %q: %w", configPath, err)
	}

	oidcCfg, err := oidcconfig.ParseConfig(data, oidcconfig.ConfigSourceSettings)
	if err != nil {
		return goerrors.Errorf("failed to parse OIDC config: %w", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	var signer oidc.TokenSigner
	if cfg.OIDCAuthndEnabled {
		signer, err = authndsigner.NewSigner(cfg, obsv)
		if err != nil {
			return goerrors.Errorf("failed to create authnd signer: %w", err)
		}
		log.Printf("Initialized OIDC service with authnd signer using URL %q", cfg.AuthndURL)
	} else {
		var shutdown func()
		signer, shutdown, err = initializeDevSigner(ctx, cfg)
		if err != nil {
			return err
		}
		defer shutdown()
	}

	svc := oidc.NewLocalService(featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentOIDCSettingsJSON: true}), signer, obsv, oidc.ServiceConfig{
		HTTPProxy:  cfg.OIDCHTTPProxy,
		HTTPSProxy: cfg.OIDCHTTPSProxy,
	})

	ownerType := sweagentd.OwnerTypeOrganization
	if !ownerIsOrg {
		ownerType = sweagentd.OwnerTypeUser
	}

	params := oidc.TokenParams{
		ActorID:           actorID,
		Actor:             actorLogin,
		ActorType:         actorType,
		OwnerID:           ownerID,
		Owner:             owner,
		OwnerType:         ownerType,
		RepoID:            repoID,
		Repo:              repo,
		AppID:             appID,
		AppClientID:       appClientID,
		AppInstallationID: appInstallationID,
	}

	_, _ = fmt.Fprintf(os.Stderr, "Processing %d OIDC config entries...\n", len(oidcCfg.OIDCConfig))

	discoveryResult, err := svc.DiscoverConfiguration(ctx, oidcCfg.OIDCConfig)
	if err != nil {
		return goerrors.Errorf("OIDC endpoint resolution failed: %w", err)
	}

	result, err := svc.ExchangeTokens(ctx, discoveryResult, params)
	if err != nil {
		return goerrors.Errorf("OIDC token exchange failed: %w", err)
	}
	if len(result.Failures) > 0 {
		for _, f := range result.Failures {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to exchange token for secret %q: %s\n", f.SecretName, f.Message)
		}
	}

	tokens := make([]tokenOutput, 0, len(result.IssuedTokens))
	for i := range result.IssuedTokens {
		t := &result.IssuedTokens[i]
		tokens = append(tokens, tokenOutput{
			SecretName:  t.ConfigEntry.FullSecretName(),
			IDToken:     t.IDToken,
			AccessToken: t.AccessToken,
		})
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")

	err = enc.Encode(tokens) //nolint:gosec // AccessToken is intentionally output by this testing CLI
	if err != nil {
		return goerrors.Errorf("failed to encode output: %w", err)
	}

	return nil
}

func initializeDevSigner(ctx context.Context, cfg *config.Config) (*devsigner.Signer, func(), error) {
	signer, err := devsigner.NewDefaultSigner(cfg.OIDCDevSignerIssuerURL, cfg.CopilotAPIURL, cfg.HTTPPort)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to create OIDC signer: %w", err)
	}
	log.Printf("Initialized OIDC service with local signer using issuer %q\nBe sure to make port %d public when running in a Codespaces environment", signer.Issuer(), cfg.HTTPPort)
	// Start an HTTP server to serve OIDC discovery endpoints so that
	// integrators can verify the tokens issued during this run.
	mux := http.NewServeMux()
	handler := signerhttp.NewHandler(signer)
	handler.RegisterRoutes(routeAdapter{mux})
	addr := fmt.Sprintf(":%d", cfg.HTTPPort)
	server := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 30 * time.Second,
		ReadTimeout:       60 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	// Bind the port synchronously so that startup failures (e.g. port
	// already in use) are reported immediately instead of racing with the
	// rest of the program.
	var lc net.ListenConfig
	ln, err := lc.Listen(ctx, "tcp", addr)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to start OIDC HTTP server on %s: %w", addr, err)
	}

	serverErr := make(chan error, 1)
	go func() {
		log.Printf("OIDC discovery server listening on %s", addr)
		listenErr := server.Serve(ln)
		if listenErr != nil && !errors.Is(listenErr, http.ErrServerClosed) {
			serverErr <- goerrors.Errorf("OIDC HTTP server error: %w", listenErr)
		}
		close(serverErr)
	}()

	shutdown := func() {
		// Use a detached context so the shutdown deadline is honoured
		// even when the parent is cancelled.
		shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
		defer cancel()

		shutdownErr := server.Shutdown(shutdownCtx)
		if shutdownErr != nil {
			log.Printf("failed to shut down OIDC HTTP server: %v", shutdownErr)
		}
		// Wait for the server goroutine to finish and log any serve errors.
		srvErr := <-serverErr
		if srvErr != nil {
			log.Printf("OIDC HTTP server error: %v", srvErr)
		}
	}

	return signer, shutdown, nil
}
