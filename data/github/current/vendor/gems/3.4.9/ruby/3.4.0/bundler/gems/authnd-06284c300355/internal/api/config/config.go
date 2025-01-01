package config

import (
	"crypto/ecdsa"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/github/authnd/internal/common/clients"
	"github.com/github/authnd/internal/common/config"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	goconfig "github.com/github/go-config"
	"github.com/lingrino/go-fault"
	"github.com/pkg/errors"
)

// Config defines the configuration to run the service.
type Config struct {
	config.CommonConfig

	Port                        int  `config:"8000,env=AUTHND_PORT"`
	LocalMobileClientServerPort int  `config:"8003,env=AUTHND_LOCAL_MOBILE_CLIENT_SERVER_PORT"`
	DisableLocalMobileClient    bool `config:"false,env=AUTHND_DISABLE_LOCAL_MOBILE_CLIENT"`

	HMACKeyList string `config:",env=AUTHND_HMAC_KEY"`

	// in production, we load the signing key from an environment variable, but we load it from a file in development/CI
	TokenExchangeSigningKeyContents string `config:",env=TOKEN_EXCHANGE_SIGNING_KEY"`
	TokenExchangeSigningKeyPath     string `config:"dev/ta-signing-key.pem,env=TOKEN_EXCHANGE_SIGNING_KEY_PATH"`
	TokenExchangeSigningKey         *ecdsa.PrivateKey

	ChatopsBaseURL         string         `config:"http://localhost:8000/_chatops,env=CHATOPS_BASE_URL"`
	ChatopsBotPublicKey    *rsa.PublicKey `config:",env=CHATOPS_BOT_PUBLIC_KEY"`
	ChatopsManualPublicKey *rsa.PublicKey `config:",env=CHATOPS_MANUAL_PUBLIC_KEY"`

	// enables primary reads. We'll only read from primary when this is enabled and our Freno checks returns unhealthy, based on the policy setup
	// for each store method. This is to prevent replication lag spikes from causing API availability incidents.
	MySQLPrimaryReadsEnabled bool `config:"false,env=MYSQL_PRIMARY_READS_ENABLED"`

	// Slack webhook
	ChatterboxToken string `config:",env=CHATTERBOX_TOKEN"`
	ChatterboxUrl   string `config:",env=CHATTERBOX_URL"`

	// chatops
	FidoChallengerURL  string `config:",env=FIDO_URL"`
	SecurityConfigPath string `config:",env=SECURITY_CONFIG_FILE"`

	// Fault injection config
	FaultEnabled       bool          `config:"false,env=FAULT_ENABLED"`
	FaultParticipation float32       `config:"0,env=FAULT_PARTICIPATION"`
	FaultErrorCode     int           `config:"0,env=FAULT_ERROR_CODE"`
	FaultSlowDuration  time.Duration `config:"0,env=FAULT_SLOW_DURATION"`

	// RSA
	IdentityPrivateKey  string `config:",env=IDENTITY_PRIVATE_KEY"`
	IdentityPublicKey   string `config:",env=IDENTITY_PUBLIC_KEY"`
	IdentityCertificate string `config:",env=IDENTITY_CERTIFICATE"`
}

// NewConfigFromEnvironment parses configuration from the environment and
// places it in a newly allocated Config struct.
func NewConfigFromEnvironment() (*Config, error) {
	cfg := &Config{}
	if err := goconfig.Load(cfg); err != nil {
		return nil, errors.WithStack(err)
	}
	cfg.ServiceName = "authnd"

	if cfg.IsCanary() {
		// chatop URL needs to match the value in #https://github.com/github/hubot-classic/blob/master/config/chatops-rpc/production.yaml
		// we have to handle canary specially since the HEAVEN_DEPLOY_ENV includes the '/canary' suffix which causes chatop errors
		// when we have a live canary deployment
		chatopEnvironment := cfg.DeploymentEnvironmentWithoutCanary()
		cfg.ChatopsBaseURL = fmt.Sprintf("https://authnd-%s.service.iad.github.net/_chatops", chatopEnvironment)
	}

	if err := cfg.LoadTokenExchangeSigningKey(); err != nil {
		return nil, errors.WithStack(err)
	}

	return cfg, nil
}

func (cfg *Config) BuildFaultHandlers(baseHandler http.Handler, logger log.Logger) (http.Handler, error) {
	if cfg.FaultEnabled {
		logger.Info("adding fault injectors", kvp.Float64("gh.authnd.request.handler.fault.participation", float64(cfg.FaultParticipation)))
	} else {
		return baseHandler, nil
	}

	injectors := []fault.Injector{}

	if cfg.FaultSlowDuration.Milliseconds() > 0 {
		slowInjector, err := fault.NewSlowInjector(cfg.FaultSlowDuration)
		if err != nil {
			return nil, errors.WithStack(err)
		}
		logger.Info("adding slow fault injector", kvp.Duration("gh.authnd.request.handler.fault.duration", cfg.FaultSlowDuration))
		injectors = append(injectors, slowInjector)
	}

	if cfg.FaultErrorCode != 0 {
		errorInjector, err := fault.NewErrorInjector(cfg.FaultErrorCode)
		if err != nil {
			return nil, errors.WithStack(err)
		}
		logger.Info("adding error fault injector", kvp.Int("gh.authnd.request.handler.fault.status_code", cfg.FaultErrorCode))
		injectors = append(injectors, errorInjector)
	}

	chainInjector, err := fault.NewChainInjector(injectors)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	errorHandler, err := fault.NewFault(chainInjector,
		fault.WithEnabled(true),
		fault.WithParticipation(cfg.FaultParticipation))
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return errorHandler.Handler(baseHandler), nil
}

// BindAddress returns the address to listen on in the form "host:port".
func (cfg *Config) BindAddress() string {
	host := "0.0.0.0"
	if cfg.IsDevelopment() {
		host = "127.0.0.1" // avoid osx firewall alert
	}

	return fmt.Sprintf("%s:%d", host, cfg.Port)
}

func (cfg *Config) LocalMobileServerClientBindAddress() string {
	host := "0.0.0.0"
	if cfg.IsDevelopment() {
		host = "127.0.0.1" // avoid osx firewall alert
	}

	return fmt.Sprintf("%s:%d", host, cfg.LocalMobileClientServerPort)
}

// GetHMACKeys returns a slice of HMAC keys from the list provided in the HMACKeyList config value
func (cfg *Config) GetHMACKeys() []string {
	return strings.Split(cfg.HMACKeyList, ",")
}

// NewChatopsHandler returns a new http.Handler for authnd chat operations.
func (cfg *Config) NewChatopsHandler(logger log.Logger, chatterboxClient clients.ChatterboxClient) (http.Handler, error) {
	namespace := "authnd"
	if cfg.DeploymentEnvironment != "production" {
		namespace = fmt.Sprintf("authnd@%s", cfg.DeploymentEnvironment)
	}

	key := cfg.ChatopsBotPublicKey
	manualKey := cfg.ChatopsManualPublicKey
	if cfg.IsDevelopmentOrTest() && key == nil {
		devKey, err := readDevChatopsKey()
		if err != nil {
			logger.WithError(err).Debug("error loading chatops dev key")
		} else {
			logger.Debug("using dev chatops key")
			key = devKey
		}
	}

	hmacKeys := cfg.GetHMACKeys()
	var hmacKey string
	if len(hmacKeys) > 0 {
		// Use the last hmac key in the list for the hmac chatop. This allows us to test the newest hmac key
		// during hmac rotation to ensure the server properly supports it before updating dependent services.
		hmacKey = hmacKeys[len(hmacKeys)-1]
	}

	return newChatopsHandler(namespace, cfg.ChatopsBaseURL, cfg.FidoChallengerURL, cfg.SecurityConfigPath,
		key, manualKey, hmacKey, chatterboxClient, cfg.IsDevelopmentOrTest())
}

// Validate enforces the invariants NewService requires.
func (cfg *Config) Validate() error {
	if cfg.HMACKeyList == "" {
		if cfg.IsDevelopmentOrTest() {
			cfg.HMACKeyList = "octocat"
		} else if !cfg.CommonConfig.IsProxima {
			return errors.New("invalid config: HMACKeyList is blank")
		}
	}

	if cfg.IsProductionLike() && strings.Contains(cfg.HMACKeyList, "octocat") {
		return errors.Errorf("invalid config: HMACKeyList includes development hmac: %q", cfg.HMACKeyList)
	}

	return nil
}

// LoadTokenExchangeSigningKey loads the token exchange signing key from the environment or a file
// depending on the environment.  In dev or test, we read key from a file and in production we read
// it from the TOKEN_EXCHANGE_SIGNING_KEY environment variable populated by Vault.
func (cfg *Config) LoadTokenExchangeSigningKey() error {
	var err error
	var privateKeyBytes []byte

	if cfg.IsDevelopmentOrTest() && cfg.TokenExchangeSigningKeyContents == "" {
		privateKeyBytes, err = os.ReadFile(cfg.TokenExchangeSigningKeyPath)
		if err != nil {
			return errors.Wrapf(err, "error reading TA private key from %s", cfg.TokenExchangeSigningKeyPath)
		}
	} else {
		privateKeyBytes = []byte(cfg.TokenExchangeSigningKeyContents)
	}
	return cfg.parseTokenExchangeSigningKey(privateKeyBytes)
}

func (cfg *Config) parseTokenExchangeSigningKey(data []byte) error {
	// Decode the PEM block
	block, _ := pem.Decode(data)
	if block == nil {
		return errors.New("unable to decoding PEM block")
	}

	// Parse the private key
	privateKey, err := x509.ParseECPrivateKey(block.Bytes)
	if err != nil {
		return errors.Wrap(err, "failed to parse private key")
	}

	cfg.TokenExchangeSigningKey = privateKey

	return nil
}

// TODO(chriskirkland): remove this once feature is read to be delivered in GHES and keypairs are added.
// ref https://github.com/github/enterprise2/pull/41746
func (cfg *Config) IdentityManagementServerEnabled() bool {
	return !cfg.IsEnterpriseServer
}
