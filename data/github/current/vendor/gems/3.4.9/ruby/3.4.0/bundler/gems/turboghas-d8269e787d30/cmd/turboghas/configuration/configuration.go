// Package configuration loads environment variables and is shared by all the turboghas commands.
package configuration

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"database/sql"
	"database/sql/driver"
	stderrors "errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"runtime/debug"
	"strconv"
	"strings"
	"syscall"
	"time"

	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"

	"github.com/github/go-http/v2/middleware/requestid"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-exceptions"
	httpexporter "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
	freno "github.com/github/go-freno-client"
	"github.com/github/go-staffbar"
	"github.com/github/go-stats"
	"github.com/github/go-twirp/client/auth"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	"github.com/github/turboghas/internal/flipper"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/lag"
	"github.com/github/turboghas/internal/mysql_dual"
	"github.com/github/turboghas/proto"
	"github.com/go-sql-driver/mysql"
	"github.com/hashicorp/go-retryablehttp"
	"github.com/kelseyhightower/envconfig"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
)

type MySQLConfiguration struct {
	MySQLDBName    string `envconfig:"MYSQL_DB_NAME"`
	MySQLUser      string `envconfig:"MYSQL_USERNAME"`
	MySQLAddr      string `envconfig:"MYSQL_ADDR"`
	MySQLPasswd    string `envconfig:"MYSQL_PASSWORD"`
	MySQLTLSConfig string `envconfig:"MYSQL_TLS" default:"false"`

	MySQLReplicaDBName    string `envconfig:"MYSQL_REPLICA_DB_NAME"`
	MySQLReplicaUser      string `envconfig:"MYSQL_REPLICA_USERNAME"`
	MySQLReplicaAddr      string `envconfig:"MYSQL_REPLICA_ADDR"`
	MySQLReplicaPasswd    string `envconfig:"MYSQL_REPLICA_PASSWORD"`
	MySQLReplicaTLSConfig string `envconfig:"MYSQL_REPLICA_TLS" default:"false"`
}

func useDefault[T string | []string](a, b T) T {
	if len(a) != 0 {
		return a
	}
	return b
}

func (config MySQLConfiguration) MysqlConfig(opts ...func(*mysql.Config)) (*mysql.Config, func(db *sql.DB)) {
	c := mysql.NewConfig()

	c.Net = "tcp"
	c.ParseTime = true
	c.InterpolateParams = true // forces statements to be prepared client-side see https://github.com/github/database-infrastructure/issues/2260#issuecomment-538617856
	c.Collation = "utf8mb4_general_ci"
	c.MultiStatements = false
	c.CheckConnLiveness = true
	c.Params = map[string]string{
		"charset": "utf8mb4",
	}
	// this allows us to check if we need to perform an upsert after attempting to update a row that may not exist
	// without it MySQL will return 0 rows changed if a row exactly matches the update statement
	c.ClientFoundRows = true

	c.DBName = config.MySQLDBName
	c.User = config.MySQLUser
	c.Addr = config.MySQLAddr
	c.Passwd = config.MySQLPasswd
	c.TLSConfig = config.MySQLTLSConfig

	for _, opt := range opts {
		opt(c)
	}

	return c, func(db *sql.DB) {
		db.SetMaxIdleConns(10)
		db.SetMaxOpenConns(25)
		// This value plus the max time of any transaction should be less
		// than the length of time that GLB allows us to keep a connection
		// open (currently 5 mins, https://github.com/github/glb/pull/2026)
		db.SetConnMaxLifetime(4*time.Minute + 30*time.Second)
	}
}

func (config MySQLConfiguration) MySQLConfigs(opts ...func(*mysql.Config)) (*mysql.Config, *mysql.Config, func(db *sql.DB)) {
	primary, fn := config.MysqlConfig(opts...)

	replica := primary.Clone()
	replica.DBName = useDefault(config.MySQLReplicaDBName, replica.DBName)
	replica.User = useDefault(config.MySQLReplicaUser, replica.User)
	replica.Addr = useDefault(config.MySQLReplicaAddr, replica.Addr)
	replica.Passwd = useDefault(config.MySQLReplicaPasswd, replica.Passwd)
	replica.TLSConfig = useDefault(config.MySQLReplicaTLSConfig, replica.TLSConfig)

	return primary, replica, fn
}

type Output string

func (f Output) Open(fn func(io.Writer) error) (err error) {
	switch f {
	case "":
		return fn(io.Discard)
	case "-":
		return fn(os.Stdout)
	default:
		file, openErr := os.OpenFile(string(f), os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0o644)
		if openErr != nil {
			return openErr
		}
		defer func() {
			closeErr := file.Close()
			if err != nil {
				err = closeErr
			}
		}()
		return fn(file)
	}
}

type HMACKeys []string

func (s *HMACKeys) Decode(value string) error {
	*s = strings.Split(strings.TrimSpace(value), " ")
	return nil
}

type Configuration struct {
	MySQLConfiguration

	Addr        string              `envconfig:"ADDR"`
	Environment fromctx.Environment `envconfig:"APP_ENV" default:"development"`
	LogLevel    string              `envconfig:"LOG_LEVEL" default:"info"`
	HMACKeys    HMACKeys            `envconfig:"TURBOGHAS_HMAC_KEY"`

	// Metrics
	StatsAddr   string        `envconfig:"STATS_ADDR"`
	StatsPeriod time.Duration `envconfig:"STATS_PERIOD" default:"10s"`

	Brokers            []string `envconfig:"BROKERS" split_words:"true"`
	KafkaVersion       string   `envconfig:"KAFKA_VERSION"`
	KafkaCACertificate string   `envconfig:"KAFKA_CA_CERTIFICATE"`

	SpokesdTwirpURL               string `envconfig:"SPOKESD_TWIRP_URL"`
	SpokesdTLSEnabled             bool   `envconfig:"SPOKESD_TLS_ENABLED"`
	SpokesdTwirpCACertificate     []byte `envconfig:"SPOKESD_TWIRP_CA_CERTIFICATE"`
	SpokesdTwirpClientCertificate []byte `envconfig:"TURBOGHAS_PRODUCTION_SPOKESD_CLIENT_CERT"`
	SpokesdTwirpClientKey         []byte `envconfig:"TURBOGHAS_PRODUCTION_SPOKESD_CLIENT_CERT_KEY"`

	GitHubTwirpURL     string `envconfig:"GITHUB_TWIRP_URL"`
	GitHubTwirpHMACKey string `envconfig:"GITHUB_TWIRP_HMAC_KEY"`

	// GHES
	GHESMigrationEventsFile string `envconfig:"GHES_MIGRATION_EVENTS_FILE"`
	GHESMigrationListFile   Output `envconfig:"GHES_MIGRATION_LIST_FILE" default:"-"`

	// Chatops
	ChatopsBaseURL      string `envconfig:"CHATOPS_BASE_URL" default:"http://localhost:8888/_chatops"`
	ChatopsBotPublicKey string `envconfig:"CHATOPS_BOT_PUBLIC_KEY"`

	FrenoAddr string `envconfig:"FRENO_ADDR"`

	// Aqueduct
	AqueductAddr          string `envconfig:"AQUEDUCT_ADDR" default:"http://localhost:18081"`
	AqueductAPIKey        string `envconfig:"AQUEDUCT_API_KEY"`
	AqueductAPIKeyVersion int    `envconfig:"AQUEDUCT_API_KEY_VERSION"`

	// Address of the Istio service mesh, if running
	IstioURL string `envconfig:"ISTIO_URL"`
}

func LoadConfiguration() (*Configuration, error) {
	config := Configuration{}
	err := envconfig.Process("", &config)
	if err != nil {
		return nil, errors.Wrap(err, "failed to load configuration")
	}

	if config.Environment.IsDevelopment() {
		config.MySQLUser = useDefault(config.MySQLUser, "root")

		if fromctx.IsGitHubCodespace {
			config.Brokers = useDefault(config.Brokers, []string{"127.0.0.1:9092"})
			config.MySQLAddr = useDefault(config.MySQLAddr, "localhost:3306")
			config.MySQLDBName = useDefault(config.MySQLDBName, "github_development_turboghas")
		} else {
			config.Brokers = useDefault(config.Brokers, []string{"localhost:9093"})
			config.MySQLAddr = useDefault(config.MySQLAddr, "localhost:13806")
			config.MySQLDBName = useDefault(config.MySQLDBName, "turboghas_development")
		}

		config.KafkaVersion = useDefault(config.KafkaVersion, "1.1.1")
		config.SpokesdTwirpURL = useDefault(config.SpokesdTwirpURL, "http://127.0.0.1:28081")
		config.GitHubTwirpURL = useDefault(config.GitHubTwirpURL, "http://api.github.localhost/internal")
		config.GitHubTwirpHMACKey = useDefault(config.GitHubTwirpHMACKey, "turboghashmac")
	}

	if config.Addr == "" {
		if config.Environment.IsDevelopment() {
			config.Addr = "127.0.0.1:8866"
		} else {
			config.Addr = ":8866"
		}
	}

	return &config, nil
}

type prefixStatter struct {
	stats.Client
	prefix string
}

func (p *prefixStatter) Counter(key string, tags stats.Tags, value int64) {
	p.Client.Counter(p.prefix+"."+key, tags, value)
}

func (p *prefixStatter) Gauge(key string, tags stats.Tags, value int64) {
	p.Client.Gauge(p.prefix+"."+key, tags, value)
}

type logAdaptor interface {
	Log(level log.Level, msg string, fields ...kvp.Field)
}

type leveledLogger struct {
	logAdaptor
}

func convertKeysAndValues(keysAndValues []any) []kvp.Field {
	fields := make([]kvp.Field, 0, len(keysAndValues)/2)
	for i := 0; i+1 < len(keysAndValues); i += 2 {
		k, ok := keysAndValues[i].(string)
		if !ok {
			continue
		}
		fields = append(fields, kvp.Any(k, keysAndValues[i+1]))
	}
	return fields
}

func (l leveledLogger) Error(msg string, keysAndValues ...any) {
	l.logAdaptor.Log(log.ErrorLevel, msg, convertKeysAndValues(keysAndValues)...)
}

func (l leveledLogger) Info(msg string, keysAndValues ...any) {
	l.logAdaptor.Log(log.InfoLevel, msg, convertKeysAndValues(keysAndValues)...)
}

func (l leveledLogger) Debug(msg string, keysAndValues ...any) {
	l.logAdaptor.Log(log.DebugLevel, msg, convertKeysAndValues(keysAndValues)...)
}

func (l leveledLogger) Warn(msg string, keysAndValues ...any) {
	l.logAdaptor.Log(log.WarnLevel, msg, convertKeysAndValues(keysAndValues)...)
}

var _ retryablehttp.LeveledLogger = &leveledLogger{}

func (config *Configuration) RetryClient(ctx context.Context) *retryablehttp.Client {
	statter := fromctx.Statter.Value(ctx)
	logger := fromctx.Logger.Value(ctx)

	retryClient := retryablehttp.NewClient()
	retryClient.Logger = leveledLogger{fromctx.Logger.Value(ctx)}
	retryClient.ResponseLogHook = func(_ retryablehttp.Logger, response *http.Response) {
		if response.StatusCode >= 400 {
			logger.Error("request failed, retrying",
				kvp.Int("status", response.StatusCode),
				kvp.Any("url", response.Request.URL),
			)
			statter.Counter("http.response", stats.Tags{"host": response.Request.Host, "code": strconv.Itoa(response.StatusCode)}, 1)
		}
	}
	retryClient.RequestLogHook = func(_ retryablehttp.Logger, request *http.Request, i int) {
		if i > 0 {
			statter.Counter("http.retry", stats.Tags{"host": request.Host, "attempt": strconv.Itoa(i)}, 1)
		}
	}

	return retryClient
}

func (config *Configuration) SpokesTransport(ctx context.Context) (http.RoundTripper, error) {
	t := http.DefaultTransport.(*http.Transport).Clone()

	if config.SpokesdTLSEnabled {
		spokesdCACertificatePool, err := x509.SystemCertPool()
		if err != nil {
			return nil, errors.Wrap(err, "could not create system cert pool")
		}
		spokesdCACertificatePool.AppendCertsFromPEM(config.SpokesdTwirpCACertificate)
		spokesdClientCertificate, err := tls.X509KeyPair(config.SpokesdTwirpClientCertificate, config.SpokesdTwirpClientKey)
		if err != nil {
			return nil, errors.Wrap(err, "could not create client certificate")
		}
		t.TLSClientConfig = &tls.Config{
			MinVersion:   tls.VersionTLS12,
			RootCAs:      spokesdCACertificatePool,
			Certificates: []tls.Certificate{spokesdClientCertificate},
		}
	}

	return AppTransport(ctx, t), nil
}

func (config *Configuration) WithContext(ctx context.Context, fn func(ctx context.Context) error) (err error) {
	signalCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGHUP, syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	ctx = fromctx.WithShutdown(ctx, signalCtx.Done())

	app, err := os.Executable()
	if err != nil {
		return errors.Wrap(err, "could not get executable name")
	}
	app = filepath.Base(app)

	ctx = fromctx.App.With(ctx, app)

	if config.IstioURL != "" {
		// attempt to shutdown the Istio service mesh as we exit
		quitURL, err := url.JoinPath(config.IstioURL, "quitquitquit")
		if err != nil {
			return err
		}
		defer func() {
			if resp, err := http.DefaultClient.Post(quitURL, "application/octet-stream", strings.NewReader("")); err == nil {
				_ = resp.Body.Close()
			}
		}()
	}

	logger, err := config.newLogger()
	if err != nil {
		return errors.Wrap(err, "failed to create logger")
	}

	statter, err := config.newStatter()
	if err != nil {
		return errors.Wrap(err, "failed to create stats client")
	}
	statter.Run()
	defer statter.Stop()

	sloTracker, err := config.newSloTracker()
	if err != nil {
		return errors.Wrap(err, "failed to create slo tracker")
	}
	sloTracker.Run()
	defer sloTracker.Stop()

	reporter, err := config.newExceptionReporter(logger, app)
	if err != nil {
		return errors.Wrap(err, "failed to create exception reporter")
	}

	ctx = fromctx.Logger.With(ctx, logger.WithFields(kvp.String("gh.turboghas.app", app)))
	ctx = fromctx.Statter.With(ctx, statter.WithTags(stats.Tags{"gh.turboghas.app": app}))
	ctx = fromctx.SLOTracker.With(ctx, sloTracker)
	ctx = fromctx.Throttler.With(ctx, config.newThrottler())
	ctx = fromctx.ExceptionReporter.With(ctx, reporter)
	ctx = fromctx.Env.With(ctx, config.Environment)
	ctx = fromctx.Lag.With(ctx, config.newLagClient(ctx))
	ctx = fromctx.QueryReporter.With(ctx, func(ctx context.Context) func(query string, duration time.Duration, results int64) {
		return staffbar.QueryReporterFromContext(ctx).Report
	})

	if config.GitHubTwirpURL != "" {
		githubSigner, err := config.GitHubClient(ctx)
		if err != nil {
			return errors.Wrap(err, "could not create github client")
		}

		flipperAPI := twirpFeatures.NewFeaturesAPIProtobufClient(config.GitHubTwirpURL, githubSigner)
		features, err := flipper.New(flipperAPI, &prefixStatter{Client: statter, prefix: "flipper"})
		if err != nil {
			return errors.Wrap(err, "failed to create flipper")
		}

		ctx = fromctx.Flipper.With(ctx, features)
	}

	defer func() {
		if r := recover(); r != nil {
			var innerErr error
			if panicErr, ok := r.(error); ok {
				innerErr = errors.Wrap(panicErr, "panic")
			} else {
				innerErr = errors.Errorf("panic: %s", r)
			}

			err = stderrors.Join(err, innerErr)
		}
		if err != nil {
			logger.WithError(err).Error("fatal error")
			fromctx.ExceptionReporter.Report(ctx, err, nil)
		}
	}()

	return fn(ctx)
}

type appTransport struct {
	next  http.RoundTripper
	agent string
}

var _ http.RoundTripper = &appTransport{}

func (t *appTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	requestid.Forward(req)
	req.Header.Set("User-Agent", t.agent)
	return t.next.RoundTrip(req)
}

func AppTransport(ctx context.Context, next http.RoundTripper) http.RoundTripper {
	version := "unknown"
	if info, ok := debug.ReadBuildInfo(); ok {
		for _, setting := range info.Settings {
			if setting.Key == "vcs.revision" {
				version = setting.Value
				break
			}
		}
	}

	return &appTransport{
		next:  next,
		agent: fmt.Sprintf("github/turboghas#%s@%s (#code-scanning)", fromctx.App.Value(ctx), version),
	}
}

func AppClient(ctx context.Context) *http.Client {
	return &http.Client{Transport: AppTransport(ctx, http.DefaultTransport)}
}

func (config *Configuration) GitHubClient(ctx context.Context) (proto.HTTPClient, error) {
	c := config.RetryClient(ctx)
	c.HTTPClient = AppClient(ctx)
	client := c.StandardClient()

	if config.GitHubTwirpHMACKey != "" {
		return auth.NewRequestHMACSigner(config.GitHubTwirpHMACKey, client)
	}

	return client, nil
}

func (config *Configuration) NewTurboghasAPIClient(client twirpTurboghas.HTTPClient) twirpTurboghas.TurboghasAPI {
	return twirpTurboghas.NewTurboghasAPIProtobufClient(config.GitHubTwirpURL, client, twirp.WithClientInterceptors(
		func(fn twirp.Method) twirp.Method {
			return func(ctx context.Context, request any) (any, error) {
				then := time.Now()
				defer func() {
					if name, ok := twirp.MethodName(ctx); ok {
						statter := fromctx.Statter.Value(ctx)
						statter.Timing("api_request", stats.Tags{"method": name}, time.Since(then))
						statter.Counter("api_request.called", stats.Tags{"method": name}, 1)
					}
				}()
				if requestid.GetGitHubRequestID(ctx) == "" {
					ctx = requestid.WithNewGitHubRequestID(ctx)
				}
				return fn(ctx, request)
			}
		},
	))
}

func (config *Configuration) newLagClient(ctx context.Context) lag.Client {
	if config.FrenoAddr != "" {
		c := AppClient(ctx)
		c.Timeout = 500 * time.Millisecond
		return lag.Cache(
			lag.FrenoClient(config.FrenoAddr, c),
			150*time.Millisecond,
		)
	}
	return lag.NullClient
}

func (config *Configuration) newLogger() (log.Logger, error) {
	provider, err := telemetry.NewFromEnv()
	if err != nil {
		return nil, errors.Wrap(err, "Failed configuring telemetry.")
	}

	var level log.Level
	switch strings.ToLower(config.LogLevel) {
	case "debug":
		level = log.DebugLevel
	case "info":
		level = log.InfoLevel
	case "error":
		level = log.ErrorLevel
	default:
		return nil, errors.Errorf("Unknown log level %v.", config.LogLevel)
	}

	return provider.Logger.WithLevel(level), nil
}

func (config *Configuration) newStatter() (stats.Client, error) {
	if config.StatsAddr != "" {
		sink, err := stats.NewUDPSink(config.StatsAddr)
		if err != nil {
			return nil, errors.Wrap(err, "failed to create stats sink")
		}

		client := stats.NewClient(sink, config.StatsPeriod, "turboghas")

		// Only Datadog supports tags. On Enterprise we have to remove all tags if we want our stats to be recorded.
		if config.Environment.IsEnterprise() {
			return stats.NewCollectdClient(client), nil
		}

		return client.WithTags(stats.Tags{"env": string(config.Environment), "application": "turboghas"}), nil
	}
	return stats.NullStatter, nil
}

func (config *Configuration) newSloTracker() (stats.Client, error) {
	if !config.Environment.IsEnterprise() && config.StatsAddr != "" {
		sink, err := stats.NewUDPSink(config.StatsAddr)
		if err != nil {
			return nil, errors.Wrap(err, "failed to create stats sink")
		}

		client := stats.NewClient(sink, config.StatsPeriod, "github_advanced_security_billing")

		return client.WithTags(stats.Tags{"deployed_to": string(config.Environment), "application": "turboghas"}), nil
	}
	return stats.NullStatter, nil
}

func (config *Configuration) newThrottler() freno.Throttler {
	if config.FrenoAddr == "" {
		return freno.DefaultThrottler
	}
	return freno.NewFrenoThrottler(config.FrenoAddr, "turboghas", "turboghas-prod")
}

func isErrType[T error](err error) bool {
	var t T
	return errors.As(err, &t)
}

func isNetworkError(err error) bool {
	return isErrType[*url.Error](err) || isErrType[*net.OpError](err)
}

func rollupFunc(err error) (info string, ok bool) {
	if errors.Is(err, mysql.ErrInvalidConn) {
		return "invalid connection", true
	}
	if errors.Is(err, driver.ErrBadConn) {
		return "driver: bad connection", true
	}
	if errors.Is(err, context.Canceled) {
		return "context canceled", true
	}
	// roll up failover errors (1290)
	if code, ok := mysql_dual.MySQLErrorNumber(err, 1290); ok {
		return fmt.Sprintf("mysql error: %d", code), true
	}
	// roll all network issues up into one umbrella alert to avoid alert noise
	// individual alerts can still be viewed in Sentry
	if isNetworkError(err) {
		return "network error", true
	}
	// group all twirp errors together based on the twirp status
	var twirpErr twirp.Error
	if errors.As(err, &twirpErr) {
		return fmt.Sprintf("twirp error: %s", twirpErr.Code()), true
	}
	return
}

func (config *Configuration) newExceptionReporter(logger log.Logger, app string) (*exceptions.Reporter, error) {
	var err error
	var exceptionExporter exceptions.Exporter = writer.NewExporter(os.Stdout)
	if os.Getenv("FAILBOT_HAYSTACK_URL") != "" {
		exceptionExporter, err = httpexporter.NewExporter()
		if err != nil {
			return nil, err
		}
	}

	errorLogger := func(reportErr, err error, payload map[string]string) {
		var fields []kvp.Field

		if err != nil {
			fields = append(fields, kvp.String("gh.turboghas.exception_error", err.Error()))
		}

		for k, v := range payload {
			fields = append(fields, kvp.String(k, v))
		}

		logger.WithError(reportErr).Error("failed to report exception", fields...)
	}

	return exceptions.NewReporter(
		exceptions.WithExporter(exceptionExporter),
		exceptions.WithStacktraceFunc(pkgerrors.NewStackTracer()),
		exceptions.WithRollupInfoFunc(rollupFunc),
		exceptions.WithApplication(app),
		exceptions.WithValues(map[string]string{
			"#gh.exception.catalog_service": "github/turboghas",
		}),
		exceptions.WithErrorLogger(errorLogger),
	)
}

func (config *Configuration) KafkaTLS() hydro.KafkaConfigOption {
	return func(cfg *hydro.KafkaConfig) error {
		if config.KafkaCACertificate != "" {
			rootCA, err := os.ReadFile(config.KafkaCACertificate)
			if err != nil {
				return errors.Wrap(err, "error reading root CA file for Kafka")

			}

			certPool := x509.NewCertPool()
			if ok := certPool.AppendCertsFromPEM(rootCA); !ok {
				return errors.New("adding root CA to cert pool for Kafka")
			}

			tlsConfiguration := &tls.Config{
				RootCAs:    certPool,
				MinVersion: tls.VersionTLS12,
			}
			return hydro.WithTLS(tlsConfiguration)(cfg)
		}
		return nil
	}
}
