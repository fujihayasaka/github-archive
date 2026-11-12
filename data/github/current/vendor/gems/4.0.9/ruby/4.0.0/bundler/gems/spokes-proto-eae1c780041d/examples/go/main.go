package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"flag"
	"fmt"
	"net/http"
	"os"

	"github.com/github/go-auth/hmac"
	"github.com/github/go/http/headers"
	"github.com/github/spokes-proto/gen/go/v1/trees"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

// Use 'go build' to set this to the current commit SHA.
var BuildVersion string

// This should be set to your app's name.
const ServiceName = "example-service"

var HMACKey = os.Getenv("HMAC_KEY")

// This will change for prod and staging.
var SpokesdURL = flag.String("url", "https://127.0.0.1:12443", "base URL for Spokes API")

func main() {
	flag.Parse()

	tlsConfig := setUpSpokesdTLSConfig()

	// Only create one http.Transport per process.
	transport := makeTransport(tlsConfig)

	// Create an HTTP client stack that will set request ID and user-agent
	// and use our TLS config.
	httpClient := &setRequestHeaders{client: &http.Client{Transport: transport}}

	// Create a client for the Trees API.
	client := trees.NewTreesAPIProtobufClient(*SpokesdURL, httpClient)

	ctx := context.Background()
	var cursor *types.Cursor

	for {
		// Build a request.
		req := trees.NewListTreesRequestWithTreeishSelector(
			types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE),
			types.NewRepository(1),
			selectors.NewTreeishSelector(types.NewTreeishWithReference(types.DefaultBranch())),
		).WithRecursive().WithCursor(cursor)

		// Send the request.
		resp, err := client.ListTrees(ctx, req)
		if err != nil {
			fmt.Printf("error: %v\n", err)
			os.Exit(1)
		}

		// Process the response.
		for _, entry := range resp.GetEntries() {
			fmt.Printf("mode:%s type:%s oid:%s path:%s\n",
				entry.GetMode().ModeString(),
				entry.GetObject().GetType().String(),
				entry.GetObject().GetOid().GetId(),
				string(entry.GetPath().GetName()))
		}

		// If there are more results, update the cursor and iterate.
		cursor = resp.GetNextCursor()
		if cursor == nil {
			break
		}
	}
}

func makeTransport(tlsConfig *tls.Config) *http.Transport {
	// When using a custom TLS config, you'll need to make an http.Transport to
	// go with it.
	transport := &http.Transport{TLSClientConfig: tlsConfig}

	// Custom http.Transport objects lose some of the defaults from
	// http.DefaultTransport, including HTTP/2 configuration. See
	// https://github.com/golang/go/blob/2d1d54808131b09da768ec334b3387ccb70562ec/src/net/http/transport.go#L38-L54
	//
	// Here are three ways to ensure your requests use HTTP/2.

	// 1. Enable it on the transport.
	transport.ForceAttemptHTTP2 = true

	// 2. Start with a clone of the default transport instead of a blank object.
	//
	//     if t, ok := http.DefaultTransport.(*http.Transport); ok {
	//         transport = t.Clone()
	//         transport.TLSClientConfig = tlsConfig
	//     }

	// 3. Use "golang.org/x/net/http2".ConfigureTransport.
	//
	//     import "golang.org/x/net/http2"
	//
	//     if err := http2.ConfigureTransport(transport); err != nil {
	//         panic(err)
	//     }

	return transport
}

func setUpSpokesdTLSConfig() *tls.Config {
	clientCert := os.Getenv("SPOKESD_CLIENT_CERT")
	clientKey := os.Getenv("SPOKESD_CLIENT_KEY")
	caChain := os.Getenv("SPOKESD_CA_CHAIN")
	if clientCert == "" || clientKey == "" || caChain == "" {
		fmt.Println("warning: TLS config not found, run 'source env.sh' before running this!")
	}

	config := &tls.Config{
		MinVersion: tls.VersionTLS12,
	}

	if clientCert != "" && clientKey != "" {
		// Initialize our client cert.
		cert, err := tls.X509KeyPair([]byte(clientCert), []byte(clientKey))
		if err != nil {
			panic(err)
		}
		config.Certificates = []tls.Certificate{cert}
	}

	if caChain != "" {
		// Set up a cert pool that includes spokesd's CA.
		caPool, err := x509.SystemCertPool()
		if err != nil {
			panic(err)
		}
		if !caPool.AppendCertsFromPEM([]byte(caChain)) {
			panic("failed to configure spokesd CA")
		}
		config.RootCAs = caPool
	}

	return config
}

type setRequestHeaders struct {
	client *http.Client
}

func (s *setRequestHeaders) Do(req *http.Request) (*http.Response, error) {
	// spokes-proto clients will typically use go-http's requestid package to forward the request ID.
	//requestid.Forward(req)

	// All spokes-proto clients should set a User-Agent string that looks like this:
	req.Header.Set("User-Agent", fmt.Sprintf("%s/%s", ServiceName, BuildVersion))

	// When using HMAC authentication, spokes-proto clients should set a
	// Request-HMAC header. Here, we set it all the time, since it will be
	// ignored if the request is also using TLS.
	//
	// In Go, this would typically be done with an
	// 'auth.NewRequestHMACSigner' http client.
	// https://github.com/github/go-twirp/blob/v0.4.1/client/auth/requesthmac.go
	req.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(HMACKey).String())

	return s.client.Do(req)
}
