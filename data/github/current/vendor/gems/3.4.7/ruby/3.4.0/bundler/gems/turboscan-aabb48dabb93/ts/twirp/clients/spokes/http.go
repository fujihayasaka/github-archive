package spokes

import (
	"crypto/tls"
	"crypto/x509"
	"net/http"

	"github.com/pkg/errors"
)

func newHttpClient(clientCert, clientKey, caChain string) (*http.Client, error) {
	tlsConfig, err := setUpSpokesdTLSConfig(clientCert, clientKey, caChain)
	if err != nil {
		return nil, err
	}

	transport := &http.Transport{TLSClientConfig: tlsConfig}
	// Custom http.Transport objects lose some of the defaults from
	// http.DefaultTransport, including HTTP/2 configuration. See
	// https://github.com/golang/go/blob/2d1d54808131b09da768ec334b3387ccb70562ec/src/net/http/transport.go#L38-L54
	transport.ForceAttemptHTTP2 = true

	return &http.Client{Transport: transport}, nil
}

func setUpSpokesdTLSConfig(clientCert, clientKey, caChain string) (*tls.Config, error) {
	if clientCert == "" || clientKey == "" || caChain == "" {
		return nil, nil
	}

	config := &tls.Config{
		MinVersion: tls.VersionTLS12,
	}

	if clientCert != "" && clientKey != "" {
		// Initialize our client cert.
		cert, err := tls.X509KeyPair([]byte(clientCert), []byte(clientKey))
		if err != nil {
			return nil, err
		}
		config.Certificates = []tls.Certificate{cert}
	}

	if caChain != "" {
		// Set up a cert pool that includes spokesd's CA.
		caPool, err := x509.SystemCertPool()
		if err != nil {
			return nil, errors.Wrap(err, "failed to initialize empty CA store for SpokesD")
		}
		if !caPool.AppendCertsFromPEM([]byte(caChain)) {
			return nil, errors.New("failed to install SpokesD cert chain onto CA store")
		}
		config.RootCAs = caPool
	}

	return config, nil
}
