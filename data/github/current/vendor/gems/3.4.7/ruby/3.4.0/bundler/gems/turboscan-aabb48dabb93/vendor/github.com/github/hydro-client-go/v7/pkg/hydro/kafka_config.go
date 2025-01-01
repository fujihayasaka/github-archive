// Connection Guide
//
// To connect to a Hydro cluster you'll need a list of its bootstrap broker
// addresses. These can be found in
// https://github.com/github/hydro-schemas/blob/master/topic-configuration/clusters.yaml.
//
// Brokers support different connection types depending on the port. For
// plaintext use port 9092. For SSL use port 9093.
//
// When creating a KafkaConfig broker addresses must include their port
// in the form of "host:port". It is critical to use the correct port. To use
// encryption see the Encryption section.
//
// Here's an example of how to create a KafkaConfig for connecting to the
// potomac cluster without encryption:
//
//	brokers := []string{
//	    "hydro-kafka-potomac.service.ac4-iad.consul:9092",
//	    "hydro-kafka-potomac.service.ash1-iad.consul:9092",
//	    "hydro-kafka-potomac.service.va3-iad.consul:9092",
//	}
//	cfg, err := NewKafkaConfig(brokers)
//
// # Encryption
//
// Hydro clusters support encryption with authentication using one-way SSL.
// This requires connecting to broker's SSL port 9093 and using a root CA
// cert to verify a broker's identity.
//
// The root CA cert can be found on production hosts at
// /etc/ssl/certs/cp1-iad-production-1487801205-root.pem. It has a long
// expiration date (many years), however when it eventually expires,
// applications will need to be redeployed with the new cert.
//
// To connect to a cluster using encryption a KafkaConfig must be created using
// NewKafkaConfig with broker addresses including port 9093 and providing a
// path to the root CA cert using the WithRootCA option.
//
// Here's an example of how to create a KafkaConfig for connecting to the
// hudson cluster with encryption:
//
//	brokers := []string{
//	    "hydro-kafka-hudson.service.ac4-iad.consul:9093",
//	    "hydro-kafka-hudson.service.ash1-iad.consul:9093",
//	    "hydro-kafka-hudson.service.va3-iad.consul:9093",
//	}
//	certPath := "/etc/ssl/certs/cp1-iad-production-1487801205-root.pem"
//	kafkaCfg, err := NewKafkaConfig(brokers, WithRootCA(certPath))
package hydro

import (
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/go-stats"
)

var defaultClientID = "hydro-kafka-go" // TODO: include semver from build arg

// Maximum message size in bytes supported by Hydro Kafka brokers.
const MaxMessageBytes = 5243000

// SetKafkaLogger set's the package level Logger used by the underlying Kafka
// client for logging connection events. The logs can be useful for
// troubleshooting connection issues. Logging is disabled by default. When a
// Logger has been set, it can be disabled by calling SetKafkaLogger with nil.
//
// Since the underlying Kafka client's Logger is at the package level it's
// recommended for this to be called from an init function.
func SetKafkaLogger(l Logger) {
	if l == nil {
		l = nilLogger
	}
	sarama.Logger = l
}

// KafkaConfigOption is a function that applies a config to a *KafkaConfig and
// returns any encountered error.
type KafkaConfigOption func(*KafkaConfig) error

// WithMaxOpenRequests is the KafkaConfigOption that sets the max amount
// in-flight requests a Kafka client is allowed to make. It returns an error if
// it's set to a value <= 1.
func WithMaxOpenRequests(n int) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		if n < 1 {
			return errors.New("max open requests must be >= 1")
		}
		cfg.maxOpenReqs = &n
		return nil
	}
}

// WithConnectionTimeout is the KafkaConfigOption that sets the duration used
// for dial, read, and write timeouts for a Kafka client. A value of 0 disables
// timeouts (not recommended).
func WithConnectionTimeout(d time.Duration) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		cfg.timeout = &d
		return nil
	}
}

// WithSSL is the KafkaConfigOption that enables SSL with the default
// configuration. It's not necessary to specify this if you're setting any
// other option such as WithRootCA, WithClientCert, or WithTLS.
func WithSSL() KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		cfg.ssl = true
		return nil
	}
}

// WithRootCA is the KafkaConfigOption that sets the path to a root CA cert file
// for authenticating broker connections when using encryption.
//
// This is optional. If SSL is enabled and a root CA is not provided, the system
// root CA will be used.
//
// See the Encryption section in the package overview for information about
// using encryption.
func WithRootCA(path string) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		if path == "" {
			return errors.New("root CA path cannot be empty")
		}
		cfg.ssl = true
		cfg.rootCAPath = path
		return nil
	}
}

// WithClientCert sets a client certificate and key used by brokers to
// authenticate the client. The certificate and key should be strings containing
// PEM-encoded data.
func WithClientCert(cert, key string) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		if len(cert) == 0 {
			return errors.New("client cert cannot be empty")
		}
		if len(key) == 0 {
			return errors.New("client cert key cannot be empty")
		}

		cfg.ssl = true
		cfg.clientCert = cert
		cfg.clientCertKey = key
		return nil
	}
}

// WithTLS is the KafkaConfigOption that sets an explicit TLS config for
// authenticating broker connections when using encryption. The *tls.Config must
// have its RootCAs field set to an *x509.CertPool containing a valid root CA
// cert.
//
// See the Encryption section in the package overview for information about
// using encryption.
func WithTLS(tls *tls.Config) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		cfg.tls = tls
		return nil
	}
}

// WithMetadataRefreshInterval is the KafkaConfigOption that sets the interval
// a Kafka client uses to refresh its cluster metadata. A value of 0 disables
// refreshing (not recommended).
func WithMetadataRefreshInterval(d time.Duration) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		cfg.metadataInterval = &d
		return nil
	}
}

// WithClientID is the KafkaConfigOption that sets the ID a Kafka client sends
// with each request. A naming scheme following "app-environment" is
// recommended e.g., "octochat-production". It returns an error when set to an
// empty string.
func WithClientID(id string) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		if id == "" {
			return errors.New("client id must not be empty")
		}
		cfg.clientID = id
		return nil
	}
}

// WithChannelBufferSize is the KafkaConfigOption that overrides the default
// channel size used internally by a Kafka client to improve throughput when
// waiting on user level code. This can be tuned to allow for better throughput
// with certain workloads when the buffer size is the bottleneck. It is set to
// 256 by default. It's not recommended to set it to a value below the default.
func WithChannelBufferSize(n int) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		if n < 1 {
			return errors.New("channel buffer size must be >= 1")
		}
		cfg.chanBufferSize = &n
		return nil
	}
}

// WithKafkaVersion is the KafkaConfigOption that controls the protocol a Kafka
// client uses derived from the specified version. It defaults to the highest
// version currently supported for Hydro Kafka clusters. It's not recommended
// to override the default.
func WithKafkaVersion(s string) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		k, err := sarama.ParseKafkaVersion(s)
		if err != nil {
			return fmt.Errorf("parsing kafka version: %w", err)
		}
		cfg.version = &k
		return nil
	}
}

// WithKafkaStats is the KafkaConfigOption that sets the stats.Client to be
// used for instrumentation. A nil value or stats.NullStatter disables
// instrumentation. It's disabled by default.
func WithKafkaStats(sc stats.Client) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		cfg.stats = sc
		return nil
	}
}

// WithKafkaStatsRate is the KafkaConfigOption that sets the rate stats are
// sampled from a Kafka client when instrumentation is enabled. This is not to
// be confused with the sample rate or reporting interval associated with a
// stats.Client. It uses DefaultKafkaSampleRate by default. It returns an error
// when set with a value below 1 second.
func WithKafkaStatsRate(d time.Duration) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		if d < time.Second {
			return errors.New("kafka stats sample rate must be >= 1s")
		}
		cfg.sampleRate = d
		return nil
	}
}

// WithKafkaLogger is the KafkaConfigOption that sets the Logger used by a
// Kafka client to log life-cycle events and internal errors. A nil value
// disables logging. Logging is disabled by default.
func WithKafkaLogger(l Logger) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		cfg.log = l
		return nil
	}
}

// WithKafkaErrorReporter is the KafkaConfigOption that sets the ErrorReporter
// to report internal errors. A nil value disables reporting. Reporting is
// disabled by default.
func WithKafkaErrorReporter(e ErrorReporter) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		cfg.errReporter = e
		return nil
	}
}

// WithSaramaConfig is the KafkaConfigOption that sets the function used to
// modify the underlying sarama.Config after all options have been applied.
// This is for advanced use cases where full control of the underlying sarama
// client's configuration is required.
//
// See the sarama.Config docs for details.
func WithSaramaConfig(fn func(*sarama.Config)) KafkaConfigOption {
	return func(cfg *KafkaConfig) error {
		cfg.overrides = append(cfg.overrides, fn)
		return nil
	}
}

// KafkaConfig is used to create and configure a Kafka client. It can be
// configured using KafkaConfigOptions. It must be created with NewKafkaConfig.
type KafkaConfig struct {
	overrides []func(*sarama.Config)

	// connection configs
	ssl           bool
	brokers       []string
	maxOpenReqs   *int
	timeout       *time.Duration
	rootCAPath    string
	clientCert    string
	clientCertKey string
	tls           *tls.Config

	// metadata configs
	metadataInterval *time.Duration

	// client configs
	clientID       string
	chanBufferSize *int
	version        *sarama.KafkaVersion

	// instrumentation
	stats       stats.Client
	sampleRate  time.Duration
	log         Logger
	errReporter ErrorReporter
}

// NewKafkaConfig creates a KafkaConfig with a list of bootstrap broker
// addresses used to connect to a cluster. Addresses must be in the form of
// "host:port". It applies each KafkaConfigOption returning any encountered
// error.
//
// See the Connection Guide and Encryption sections in the package overview for
// configuration details.
func NewKafkaConfig(brokers []string, opts ...KafkaConfigOption) (*KafkaConfig, error) {
	if len(brokers) == 0 {
		return nil, errors.New("no brokers provided")
	}

	kc := &KafkaConfig{
		brokers: brokers,
	}

	for _, o := range opts {
		if err := o(kc); err != nil {
			return nil, fmt.Errorf("applying KafkaConfigOption: %w", err)
		}
	}

	if kc.ssl {
		if kc.tls == nil {
			kc.tls = &tls.Config{
				MinVersion: tls.VersionTLS12,
			}
		}

		if kc.rootCAPath != "" {
			rootCA, err := os.ReadFile(kc.rootCAPath)
			if err != nil {
				return nil, fmt.Errorf("reading root CA cert: %w", err)
			}

			certPool := x509.NewCertPool()
			if ok := certPool.AppendCertsFromPEM(rootCA); !ok {
				return nil, errors.New("failed to add root CA to cert pool")
			}
			kc.tls.RootCAs = certPool
		}

		if kc.tls.RootCAs == nil {
			rootCAs, err := x509.SystemCertPool()
			if err != nil {
				return nil, fmt.Errorf("loading system cert pool: %w", err)
			}
			kc.tls.RootCAs = rootCAs
		}

		if len(kc.clientCert) > 0 {
			cert, err := tls.X509KeyPair([]byte(kc.clientCert), []byte(kc.clientCertKey))
			if err != nil {
				return nil, fmt.Errorf("failed to load client cert: %w", err)
			}
			kc.tls.Certificates = append(kc.tls.Certificates, cert)
		}
	}

	if kc.clientID == "" {
		kc.clientID = defaultClientID
	}

	if kc.version == nil {
		kc.version = &sarama.V2_2_0_0
	}

	if kc.stats == nil {
		kc.stats = stats.NullStatter
	}

	if kc.sampleRate == 0 {
		kc.sampleRate = DefaultKafkaSampleRate
	}

	if kc.log == nil {
		kc.log = nilLogger
	}

	if kc.errReporter == nil {
		if kc.log != nil {
			kc.errReporter = &LogErrorReporter{Logger: kc.log}
		} else {
			kc.errReporter = nilErrorReporter
		}
	}

	return kc, nil
}

func (kc KafkaConfig) toSarama() *sarama.Config {
	sc := sarama.NewConfig()

	// sarama.Config.Net configs
	if kc.maxOpenReqs != nil {
		sc.Net.MaxOpenRequests = *kc.maxOpenReqs
	}
	if kc.timeout != nil {
		sc.Net.DialTimeout = *kc.timeout
		sc.Net.ReadTimeout = *kc.timeout
		sc.Net.WriteTimeout = *kc.timeout
	}
	if kc.tls != nil {
		sc.Net.TLS.Enable = true
		sc.Net.TLS.Config = kc.tls
	}

	// sarama.Config.Metadata configs
	if kc.metadataInterval != nil {
		sc.Metadata.RefreshFrequency = *kc.metadataInterval
	}
	sc.Metadata.Full = false // only request necessary metadata

	// sarama.Config configs
	sc.ClientID = kc.clientID
	if kc.chanBufferSize != nil {
		sc.ChannelBufferSize = *kc.chanBufferSize
	}
	sc.Version = *kc.version

	return sc
}
