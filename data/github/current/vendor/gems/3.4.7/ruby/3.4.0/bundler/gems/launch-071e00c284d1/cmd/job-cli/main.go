package main

import (
	"context"
	"fmt"
	"os"
	"runtime/debug"

	"github.com/pkg/errors"
	errs "github.com/pkg/errors"

	"github.com/github/go-kvp"

	"github.com/github/launch/cli"
	"github.com/github/launch/pkg/abreaker"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/apphttp"
)

func main() {

	// Required by mu for build flags and such.
	cli.ParseFlags()

	jobName := getJobName()

	metadata := cli.GetApplicationMetadata(jobName)

	ctx, err := appcontext.InitializeWithRequestID(context.Background(), metadata, jobName)
	if err != nil {
		exit(errs.Wrap(err, "could not setup metadata"))
	}

	if err := launchconfig.LoadGlobalConfig(); err != nil {
		exit(errs.Wrap(err, "could not load common config"))
	}

	cfg, err := loadConfig()
	if err != nil {
		exit(errs.Wrap(err, "could not load config"))
	}

	obs, obsCloser := getObservability(cfg)
	defer obsCloser()
	obs.Log(ctx, "configured logger and statter", kvp.String("server.address", cfg.StatsAddr))

	defaultHTTPClient := apphttp.NewClient(apphttp.WithObservability(obs, cfg.RoundTripperConfig))

	conn, err := getDbConn(cfg, obs.Statter)
	defer func() { _ = conn.Close() }()
	if err != nil {
		exit(errs.Wrap(err, "could not get a DB connection"))
	}

	readOnlyConn, err := getRODbConn(cfg, obs.Statter)
	defer func() { _ = readOnlyConn.Close() }()
	if err != nil {
		exit(errs.Wrap(err, "could not get a ro DB connection"))
	}

	redisBreaker, err := abreaker.NewRedisBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		exit(errs.Wrap(err, "could not create redis breaker"))
	}
	cache, doneCache, err := getCache(ctx, cfg, obs, redisBreaker)
	if err != nil {
		exit(errs.Wrap(err, "cloud not create cache"))
	}
	defer doneCache()

	dbThrottlerFunc := getThrottlerFunc(cfg)

	ghTwirpClient, err := getGitHubTwirpClient(ctx, cfg, defaultHTTPClient, obs, metadata, cache.GitHubTwirp())
	if err != nil {
		exit(errs.Wrap(err, "could not get a github twirp client"))
	}

	tok, err := getTokenService(ctx, cfg, defaultHTTPClient, obs, metadata, cache.GitHub(), ghTwirpClient)
	if err != nil {
		exit(errs.Wrap(err, "could not get the token service"))
	}

	gcf, err := getGithubClientFactory(ctx, cfg, defaultHTTPClient, obs, tok, metadata, ghTwirpClient)
	if err != nil {
		exit(errs.Wrap(err, "could not get a github client factory"))
	}

	dbBreaker, err := abreaker.NewLaunchDBClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		exit(errs.Wrap(err, "could not get breaker"))
	}

	dbROBreaker, err := abreaker.NewLaunchRODBClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		exit(errs.Wrap(err, "could not build breaker for launch ro db client"))
	}

	scf, err := getServiceClientFactories(ctx, cfg, obs, conn, cache, metadata, dbBreaker, ghTwirpClient)
	if err != nil {
		exit(errs.Wrap(err, "could not get a service client factory and/or a bearer token client factory"))
	}

	breaker, err := abreaker.NewFrenoClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		exit(errs.Wrap(err, "could not get breaker"))
	}
	frenoClient, err := getFrenoClient(cfg, obs, defaultHTTPClient, breaker)
	if err != nil {
		exit(errs.Wrap(err, "could not get a freno client"))
	}

	hjc := cache.HealingJob()

	defer func() {
		if rvr := recover(); rvr != nil {

			var err error
			if e, ok := rvr.(error); ok {
				err = e
			} else {
				err = fmt.Errorf("%v", rvr)
			}

			obs.Report(ctx, errors.WithStack(err), kvp.String("exception_detail", string(debug.Stack())))
			os.Exit(1)
		}
	}()

	rootCmd := getRootCommand(ctx, obs, conn, readOnlyConn, dbThrottlerFunc, gcf, scf, ghTwirpClient, frenoClient, hjc, dbBreaker, dbROBreaker, cfg.IsMultiTenant)
	if err := rootCmd.ExecuteContext(ctx); err != nil {
		exit(errs.Wrap(err, "error executing command"))
	}
}

func exit(err error) {
	fmt.Println(err.Error())
	os.Exit(1)
}

// getJobName peeks at the process ars to figure out what job we're running.
// This does assume that at least two arguments will be passed to job-cli
// when called. If that assumptions isn't met, we return a generic name.
//
// E.g. bin/job-cli jobs whateverJob becomes job-cli-whateverJob
func getJobName() string {
	if len(os.Args) < 2 {
		return "job-cli-unknown-job"
	}
	return "job-cli-" + os.Args[2]
}
