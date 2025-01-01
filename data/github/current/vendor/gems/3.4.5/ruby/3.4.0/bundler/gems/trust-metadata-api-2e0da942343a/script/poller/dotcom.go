package main

/*
   Simple script to create a periodic read or write load against a local
   instance of TMA. If run with default parameters, it will execute a
   single transaction only, to perform periodic requests, set the period
   attribute to the desired period in milliseconds.
*/

import (
	"bytes"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/github/go-auth/bodyhmac"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/trust-metadata-api/pkg/auth"
)

func main() {
	var attestation = flag.String("attestation", "test/data/sigstore.js-3.0.0.bundle.json", "attestation to store")
	var client = flag.String("request-client-name", "dotcom", "request domain id")
	var hmacKey = flag.String("hmac-key", "dotcomsecretkey", "HMAC key for use in the request")
	var timeout = flag.Int("timeout", 5, "timeout in seconds")
	var writer = flag.Bool("writer", false, "write or read attestations")
	var period = flag.Int("period", 0, "period in milliseconds")
	var targetStaging = flag.Bool("target-staging", false, "target staging environment")
	var err error
	var body string
	var url string

	flag.Parse()

	if *hmacKey == "" || *client == "" {
		panic("attestation, hmac-key, and request-client-name must be defined")
	}

	var baseURL = "http://localhost:8337"
	if *targetStaging {
		fmt.Println("targeting staging deployment")
		baseURL = "https://trust-metadata-api-staging.githubapp.com"
	}
	if *writer {
		fmt.Println("writing attestation")
		var ab []byte

		ab, err = os.ReadFile(*attestation)
		if err != nil {
			panic(err)
		}
		body = fmt.Sprintf("{\"bundle\":%s,\"repository_id\": \"1\", \"owner_id\": \"1\"}",
			string(ab),
		)
		url = fmt.Sprintf("%s/twirp/github.trust_metadata_api.GitHubAPI/CreateAttestationByOwnerRepository", baseURL)
	} else {
		fmt.Println("fetching attestation summaries")
		url = fmt.Sprintf("%s/twirp/github.trust_metadata_api.GitHubAPI/ListAttestationSummariesByRepository", baseURL)
		body = `{"repository_id": "1", "owner_id": "1", "per_page":"30"}`
	}

	hmacVal, err := bodyhmac.CreateHeader([]byte(body), []byte(*hmacKey))
	if err != nil {
		panic(err)
	}

	var dur = time.Duration(*timeout) * time.Second

	for {
		err = post(url,
			*client,
			hmacVal,
			[]byte(body),
			dur,
		)
		if err != nil {
			fmt.Println(err)
		}
		if *period == 0 {
			break
		}
		time.Sleep(time.Duration(*period) * time.Millisecond)
	}
}

var counter = 0

func post(url, client, hmacVal string, body []byte, timeout time.Duration) error {
	counter++
	req, err := http.NewRequest(http.MethodPost,
		url,
		bytes.NewReader(body))
	if err != nil {
		panic(err)
	}

	req.Header.Add(headers.RequestBodyHMAC, hmacVal)
	req.Header.Add(auth.HMACClientHeader, client)
	req.Header.Add("Content-Type", "application/json")

	httpClient := http.Client{
		Timeout: timeout,
	}
	start := time.Now()
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	elapsed := time.Since(start)
	fmt.Printf("%d request time: %s\n", counter, elapsed)

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status code %d", resp.StatusCode)
	}

	bb, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	resp.Body.Close()
	fmt.Printf("%d read %d bytes\n", counter, len(bb))

	return nil
}
