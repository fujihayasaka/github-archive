package main

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
	reqURL := flag.String("request-url", "", "request URL")
	reqBody := flag.String("request-body", "{}", "stringified JSON request body")
	reqFile := flag.String("request-file", "", "file containing JSON request body")
	client := flag.String("request-client-name", "{}", "request domain id")
	hmacKey := flag.String("hmac-key", "", "HMAC key for use in the request")
	timeout := flag.Int("timeout", 5, "timeout in seconds")

	flag.Parse()

	if *reqURL == "" || *hmacKey == "" || *client == "" {
		panic("request-url, hmac-key, and request-client-name must be defined")
	}

	var reqBytes []byte
	if *reqFile != "" {
		var err error
		reqBytes, err = os.ReadFile(*reqFile)
		if err != nil {
			panic(err)
		}
	} else {
		reqBytes = []byte(*reqBody)
	}

	hmacHeaderVal, err := bodyhmac.CreateHeader(reqBytes, []byte(*hmacKey))
	if err != nil {
		panic(err)
	}

	req, err := http.NewRequest(http.MethodPost, *reqURL, bytes.NewReader(reqBytes))
	if err != nil {
		panic(err)
	}

	req.Header.Add(headers.RequestBodyHMAC, hmacHeaderVal)
	req.Header.Add(auth.HMACClientHeader, *client)
	req.Header.Add("Content-Type", "application/json")

	httpClient := http.Client{Timeout: time.Duration(*timeout) * time.Second}
	resp, err := httpClient.Do(req)
	if err != nil {
		panic(err)
	}

	if resp.StatusCode != http.StatusOK {
		panic(fmt.Sprintf("unexpected status code %d", resp.StatusCode))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		panic(err)
	}

	resp.Body.Close()
	fmt.Println(string(body))
}
