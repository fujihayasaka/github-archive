package main

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/okta"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	goconfig "github.com/github/go-config"
	"github.com/pkg/errors"
)

type ProxyConfig struct {
	Backend    string `config:",env=ADMIN_TCP_ADDRESS"`
	Username   string `config:",env=OKTA_TEST_USERNAME"`
	TCPAddr    string `config:",env=OKTA_PROXY_TCP_ADDRESS"`
	HMACSecret string `config:",env=OKTA_PROXY_HMAC_SECRET"`
}

func main() {
	if err := realMain(); err != nil {
		fmt.Printf("failed to run service: %v\n", err)
		os.Exit(1)
	}
}

func realMain() error {
	cfg, _ := config.Load()

	ctx := context.Background()
	telem, err := telemetry.NewFromEnv()
	if err != nil {
		panic("failed configuring telemetry")
	}
	defer func() {
		if err := telem.Shutdown(ctx); err != nil {
			panic("failed to shutdown telemetry")
		}
	}()

	proxyConfig := &ProxyConfig{}

	if err := goconfig.Load(proxyConfig); err != nil {
		return errors.Wrap(err, "failed to load configuration")
	}

	logger := cfg.ConfigureLogger(telem.Logger, "OktaProxy")
	logger.Info("Look at config", kvp.String("cli", fmt.Sprintf("%+v", proxyConfig)))

	logger.Info("initializing service")

	backendURL, err := url.Parse(proxyConfig.Backend)
	if err != nil {
		logger.WithError(err).Error("failed to parse backend url")
		panic("invalid backend url")
	}

	proxy := httputil.NewSingleHostReverseProxy(backendURL)
	proxy.Transport = okta.RoundTripper(proxyConfig.Username, []byte(proxyConfig.HMACSecret), nil)

	err = http.ListenAndServe(proxyConfig.TCPAddr, proxy)
	if err != nil {
		logger.WithError(err).Error("failed to start server")
		defer os.Exit(1)
	}

	return nil
}
