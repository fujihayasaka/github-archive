package cmd

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/github"
	"github.com/github/migrations-vnext/internal/pkg/gitsync"
	"github.com/github/migrations-vnext/internal/pkg/retry"
	"github.com/github/migrations-vnext/internal/pkg/servermigrator"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/spf13/cobra"
)

var (
	rootCmd = &cobra.Command{
		Long:  "Migrate resources from GitHub Enterprise Server to GitHub Enterprise Cloud.",
		RunE:  runRootCmd,
		Short: "The GHES resource migrator.",
		Use:   "ghes-resource-migrator",
	}
)

type (
	// targetAPI is an alias for the MigrationTargetAPI interface.
	targetAPI servermigrator.MigrationTargetAPI

	// stopFn is a function that stops a running process.
	stopFn func()
)

//nolint:gochecknoinits // Using an `init` function to add flags is standard for spf13/cobra
func init() {
	// Add global flags
	rootCmd.Flags().BoolP("dry-run", "d", false, "Operate in dry-run mode. Performs no migrations, but saves a list of actions it would have taken.")

	rootCmd.Flags().String("ghes-token", "", "Token which will be used to authenticate against the GHES instance.")
	rootCmd.Flags().String("ghes-url", "http://localhost:80", "URL of the Enterprise Server instance.")

	rootCmd.Flags().String("repository", "", "The repository name (i.e. owner/repository).")
	rootCmd.Flags().String("migration-target-url", "http://api.avocado-gmbh.ghe.localhost", "The base URL of the migration target API.")
	rootCmd.Flags().String("migration-target-git-url", "http://avocado-gmbh.ghe.localhost.git", "The base URL for Git operations on the migration target.")
	rootCmd.Flags().String("migration-target-pat", "", "The personal access token to use for the migration target API.")

	rootCmd.Flags().String("wal-dir-path", "wal", "If set, the migrator will write events to a WAL dir at this path before processing them.")
	rootCmd.Flags().String("webhook-url", "", "Location to configure webhooks (e.g. crawler API).")
	rootCmd.Flags().String("webhook-id-file", "webhook-id", "Location to store the webhook ID.")

	rootCmd.Flags().String("resource-bloom-filter-path", "resource-bf.bin", "If set to a file path, a bloom filter will be created and used to prevent duplicate resources from being sent to the migration target.")

	rootCmd.Flags().String("git-repo-path", "", "Path to the local repository on disk. Can be found at /stafftools/repositories/{owner}/{repo}/disk")
	rootCmd.Flags().Duration("git-sync-interval", 20*time.Second, "Interval between git sync attempts")

	rootCmd.Flags().String("listen-addr", "localhost:9178", "The ip:port that the migrator will listen on for webhooks.")

	_ = rootCmd.MarkFlagRequired("repository")
	_ = rootCmd.MarkFlagRequired("ghes-token")
	_ = rootCmd.MarkFlagRequired("ghes-url")
}

func runRootCmd(cmd *cobra.Command, _ []string) error {
	// set up telemetry and logging
	telemetryProvider, err := telemetry.NewFromEnv()
	if err != nil {
		return fmt.Errorf("error creating telemetry proviider: %w", err)
	}

	logger := telemetryProvider.Logger.Named("ghes-resource-migrator")
	statter := stats.NewClient(os.Stdout, time.Second, "ghes-resource-migrator")
	statter.Run()
	defer statter.Stop()

	// set up context that handles the process lifecycle
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// parse the repository slug
	owner, repo, err := toOwnerRepo(cmd)
	if err != nil {
		return fmt.Errorf("error parsing repository slug: %w", err)
	}

	// create the GitHub client
	ghClient, err := createGithubClient(cmd)
	if err != nil {
		return fmt.Errorf("error creating GitHub client: %w", err)
	}

	// create a channel to handle errors from the WAL target and the HTTP server
	errC := make(chan error, 3)

	// create the target client
	target, stopWal, err := createTargetClient(ctx, errC, cmd, logger)
	if err != nil {
		return fmt.Errorf("error creating target client: %w", err)
	}

	// create the server migrator and start it
	stopServer, err := createServerMigrator(ctx, cmd, errC, target, ghClient, owner, repo, logger, statter)
	if err != nil {
		return fmt.Errorf("error creating server migrator: %w", err)
	}

	// set up webhook
	if err := setupWebhook(ctx, cmd, ghClient, owner, repo, logger); err != nil {
		return fmt.Errorf("error setting up webhooks: %w", err)
	}

	// set up git syncer
	stopGitSyncer, err := setupGitSyncer(ctx, cmd, logger, statter)
	if err != nil {
		return fmt.Errorf("error setting up git syncer: %w", err)
	}

	// set up resource fetcher
	stopResourceFetcher, err := setupResourceFetcher(ctx, errC, cmd, ghClient, owner, repo, logger)
	if err != nil {
		return fmt.Errorf("error setting up resource fetcher: %w", err)
	}

	// Create a channel to handle OS signals
	stopC := make(chan os.Signal, 1)
	signal.Notify(stopC, os.Interrupt, syscall.SIGTERM)

	// wait for either an error or an OS signal
	select {
	case <-stopC:
		logger.Info("received interrupt signal, shutting down")
	case err := <-errC:
		logger.WithError(err).Error("got an error, shutting down")
	}

	// shut down all components
	cancel()
	stopServer()
	stopWal()
	stopGitSyncer()
	stopResourceFetcher()

	return nil
}

// setupResourceFetcher sets up the resource fetcher for the given repository
func setupResourceFetcher(
	ctx context.Context,
	errC chan error,
	cmd *cobra.Command,
	ghClient *github.Client,
	owner string,
	repo string,
	logger log.Logger,
) (stopFn, error) {
	bloomFilterPath, err := cmd.Flags().GetString("resource-bloom-filter-path")
	if err != nil {
		return nil, fmt.Errorf("error getting resource-bloom-filter-path argument: %w", err)
	}
	esURL, err := cmd.Flags().GetString("ghes-url")
	if err != nil {
		return nil, fmt.Errorf("error getting ghes-url argument: %w", err)
	}
	dryRun, err := cmd.Flags().GetBool("dry-run")
	if err != nil {
		return nil, fmt.Errorf("error getting dry-run argument: %w", err)
	}

	fetcher := servermigrator.NewResourceFetcher(ctx, ghClient, owner, repo)

	var targetClient servermigrator.MigrationTargetAPI
	if !dryRun {
		migrationTargetURL, err := cmd.Flags().GetString("migration-target-url")
		if err != nil {
			return nil, fmt.Errorf("error getting migration-target-url argument: %w", err)
		}
		if migrationTargetURL == "" {
			return nil, errors.New("migration-target-url is required")
		}
		migrationTargetPAT, err := cmd.Flags().GetString("migration-target-pat")
		if err != nil {
			return nil, fmt.Errorf("error getting migration-target-pat argument: %w", err)
		}
		if migrationTargetPAT == "" {
			return nil, errors.New("migration-target-pat is required")
		}
		targetClient = servermigrator.NewMigrationTargetClient(migrationTargetURL, migrationTargetPAT)
	}
	filter, err := createFilter(bloomFilterPath)
	if err != nil {
		return nil, fmt.Errorf("error creating resource filter: %w", err)
	}
	stop := func() {
		if err := filter.save(); err != nil {
			logger.WithError(err).Error("error saving resource filter")
		}
	}

	go func() {
		for resource := range fetcher.All() { //nolint:contextcheck // we'll address this later
			if ctx.Err() != nil {
				logger.Info("stopping resource fetcher")
				return
			}

			if dryRun {
				logger.Info("dry run mode, resource fetched", kvp.Any("resource", resource))
				continue
			}

			// check if the resource is already in the bloom filter
			exists, err := filter.contains(resource)
			if err != nil {
				errC <- fmt.Errorf("error checking bloom filter: %w", err)
				return
			}
			if exists {
				logger.Info("resource already exists in bloom filter, skipping", kvp.Any("resource", resource))
				continue
			}

			// fn is a function that sends the resources to the target that will be retried
			fn := func() error { return targetClient.SendResources(ctx, esURL, []*v1.Resource{resource}) }
			// cfg is the backoff configuration for retrying failed requests
			cfg := backoff.WithContext(retryCfg(), ctx)
			// execute fn with retries
			if err := retry.Retry(fn, cfg, logger); err != nil {
				errC <- fmt.Errorf("error sending resources: %w", err)
				return
			}

			// add the resource to the bloom filter
			if err := filter.add(resource); err != nil {
				errC <- fmt.Errorf("error adding resource to bloom filter: %w", err)
				return
			}
		}
		if fetcher.Error() != nil {
			errC <- fmt.Errorf("error fetching resources: %w", fetcher.Error())
		}
	}()

	return stop, nil
}

// setupGitSyncer sets up the git syncer for the given repository by creating a new git syncer
// and starting it.
func setupGitSyncer(ctx context.Context, cmd *cobra.Command, logger log.Logger, statter *stats.Statsd) (stopFn, error) {
	gitRepoPath, err := cmd.Flags().GetString("git-repo-path")
	if err != nil {
		return nil, fmt.Errorf("error getting git-repo-path argument: %w", err)
	}

	migrationTargetGitURL, err := cmd.Flags().GetString("migration-target-git-url")
	if err != nil {
		return nil, fmt.Errorf("error getting migration-target-git-url argument: %w", err)
	}
	gitSyncInterval, err := cmd.Flags().GetDuration("git-sync-interval")
	if err != nil {
		return nil, fmt.Errorf("error getting git-sync-interval argument: %w", err)
	}

	if gitRepoPath == "" || migrationTargetGitURL == "" {
		logger.Warn("no git repo path or migration target git URL provided, skipping git syncer setup")
		return func() {}, nil
	}

	gitSyncer, err := gitsync.New(
		gitsync.WithGitRepoPath(gitRepoPath),
		gitsync.WithMigrationTargetGitURL(migrationTargetGitURL),
		gitsync.WithLogger(logger),
		gitsync.WithStatter(statter),
		gitsync.WithSyncInterval(gitSyncInterval),
	)
	if err != nil {
		return func() {}, fmt.Errorf("failed to create git syncer: %w", err)
	}

	_, err = gitSyncer.StartAsync(ctx)
	if err != nil {
		return func() {}, fmt.Errorf("failed to start git sync: %w", err)
	}

	return gitSyncer.Shutdown, nil
}

// setupWebhook sets up webhooks for the given repository by creating a new webhook (if needed) and
// redelivering any failed webhooks.
func setupWebhook(ctx context.Context, cmd *cobra.Command, client *github.Client, owner, repo string, logger log.Logger) error {
	// It's fine to ignore the errors here, as neither webhook ID file nor webhook URL are required.
	webhookIDFile, err := cmd.Flags().GetString("webhook-id-file")
	if err != nil {
		return fmt.Errorf("error getting webhook-id-file argument: %w", err)
	}
	webhookURL, err := cmd.Flags().GetString("webhook-url")
	if err != nil {
		return fmt.Errorf("error getting webhook-url argument: %w", err)
	}
	if webhookURL != "" {
		if err := createWebhookForRepository(ctx, webhookIDFile, client, owner, repo, webhookURL, logger); err != nil {
			return fmt.Errorf("error creating webhook: %w", err)
		}
	} else {
		logger.Warn("no webhook URL provided, skipping webhook creation")
	}
	go func() {
		err := redeliverFailedWebhooks(ctx, webhookIDFile, client, owner, repo, logger)
		if err != nil {
			logger.WithError(err).Error("error redelivering failed webhooks")
		}
	}()
	return nil
}

// createGithubClient creates a new GitHub client using the provided command flags.
func createGithubClient(cmd *cobra.Command) (*github.Client, error) {
	esURL, err := cmd.Flags().GetString("ghes-url")
	if err != nil {
		return nil, fmt.Errorf("error getting ghes-url argument: %w", err)
	}
	authToken, err := cmd.Flags().GetString("ghes-token")
	if err != nil {
		return nil, fmt.Errorf("error getting ghes-token argument: %w", err)
	}
	return github.New(esURL, esURL, authToken)
}

// createTargetClient creates a new migration target client using the provided command flags.
// The target client is responsible for sending resources and events to the migration target, i.e: gh/gh.
// If a WAL path is provided, the target client will use a WAL to store events before sending them to
// the migration target.
func createTargetClient(ctx context.Context, errC chan error, cmd *cobra.Command, logger log.Logger) (target targetAPI, stop stopFn, err error) {
	migrationTargetURL, err := cmd.Flags().GetString("migration-target-url")
	if err != nil {
		return nil, nil, fmt.Errorf("error getting migration-target-url argument: %w", err)
	}
	migrationTargetPAT, err := cmd.Flags().GetString("migration-target-pat")
	if err != nil {
		return nil, nil, fmt.Errorf("error getting migration-target-pat argument: %w", err)
	}
	path, err := cmd.Flags().GetString("wal-dir-path")
	if err != nil {
		return nil, nil, fmt.Errorf("error getting wal-dir-path argument: %w", err)
	}
	defer logger.Info("wal support", kvp.Bool("enabled", path != ""))

	// create the target client
	ghTargetClient := servermigrator.MigrationTargetAPI(servermigrator.NewMigrationTargetClient(migrationTargetURL, migrationTargetPAT))

	// if no WAL path is provided, return the target client, i.e: no WAL support as we write directly to the target
	if path == "" {
		return ghTargetClient, func() {}, nil
	}

	// stopC is a channel that is used to signal the WAL has stopped
	stopC := make(chan struct{}, 1)

	// create the WAL target
	walTarget, err := createWalTarget(ctx, path, stopC, errC, ghTargetClient, logger)
	if err != nil {
		return nil, func() {}, fmt.Errorf("error creating wal target: %w", err)
	}

	// stop function waits for the wal target to finish to ensure all events are flushed to disk
	stop = func() {
		logger.Info("waiting for wal target to finish...")
		<-stopC
		logger.Info("wal target finished")
	}

	return walTarget, stop, nil
}

// createWalTarget creates a new WAL target using the provided path and target client and starts the
// running the WAL target in a separate goroutine.
func createWalTarget(ctx context.Context, path string, stopC chan struct{}, errC chan error, client targetAPI, logger log.Logger) (*WALTarget, error) {
	walTarget, err := NewWALTarget(path, client, logger)
	if err != nil {
		return nil, fmt.Errorf("error creating WAL target: %w", err)
	}
	go func() {
		defer close(stopC)
		err := walTarget.Run(ctx)
		err = errors.Join(err, walTarget.Close())
		if err != nil {
			errC <- fmt.Errorf("error running wal target: %w", err)
		}
	}()
	return walTarget, nil
}

func createServerMigrator(
	ctx context.Context,
	cmd *cobra.Command,
	errC chan error,
	targetClient targetAPI,
	ghClient *github.Client,
	owner string,
	repository string,
	logger log.Logger,
	statter *stats.Statsd,
) (stopFn, error) {
	// Get the listen address to listen on for webhooks
	listenAddr, err := cmd.Flags().GetString("listen-addr")
	if err != nil {
		return nil, errors.New("could not get the value of the listen-addr flag")
	}

	// Create the resource fetcher that will be used to fetch resources from the source
	// using public APIs (both REST and GraphQL)
	fetcher := servermigrator.NewResourceFetcher(ctx, ghClient, owner, repository)
	org, err := fetcher.InitOrg(ctx)
	if err != nil {
		return nil, fmt.Errorf("error initializing fetcher org: %w", err)
	}

	// Create the server migrator that will be used to migrate resources from the source using
	// public APIs (both REST and GraphQL) and listening for webhooks.
	m, err := servermigrator.New(
		servermigrator.WithListenAddr(listenAddr),
		servermigrator.WithLogger(logger),
		servermigrator.WithOrganization(org),
		servermigrator.WithMigrationTargetClient(targetClient),
		servermigrator.WithResourceFetcher(fetcher),
		servermigrator.WithStatter(statter),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create instance of servermigrator: %w", err)
	}

	// Run the server migrator in a separate goroutine
	go func() {
		if err := m.Run(); err != nil {
			errC <- fmt.Errorf("error running server migrator: %w", err)
		}
	}()

	// Create a function to stop the server migrator
	stopServer := func() { //nolint:contextcheck // we explicitly not pass global ctx to give the server some time to shut down
		logger.Info("stopping server migrator")
		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer shutdownCancel()
		if err := m.Shutdown(shutdownCtx); err != nil {
			logger.WithError(err).Error("error shutting down server migrator")
		}
		logger.Info("server migrator stopped")
	}

	logger.Info("starting ghes-resource-migrator", kvp.String("listen.addr", listenAddr))

	return stopServer, nil
}

// toOwnerRepo splits a repository slug into its owner and repository components.
func toOwnerRepo(cmd *cobra.Command) (owner, repo string, err error) {
	slug, err := cmd.Flags().GetString("repository")
	if err != nil {
		return "", "", fmt.Errorf("error getting repository argument: %w", err)
	}
	slugSplit := strings.Split(slug, "/")
	if len(slugSplit) != 2 {
		return "", "", errors.New("invalid repository format, expected 'owner/repository'")
	}
	return slugSplit[0], slugSplit[1], nil
}
