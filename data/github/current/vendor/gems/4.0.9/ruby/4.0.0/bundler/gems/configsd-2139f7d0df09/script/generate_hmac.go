// Package main generates an HMAC signature for HTTP requests.
package main

import (
	"fmt"
	"os"

	"github.com/github/go-auth/hmac"
)

func main() {
	key := os.Getenv("APP_HMAC_KEY_PRIMARY")
	if key == "" {
		_, _ = fmt.Fprintln(os.Stderr, "APP_HMAC_KEY_PRIMARY not set")
		os.Exit(1)
	}
	sig := hmac.NewRequestHMAC(key)
	fmt.Print(sig.String())
}
