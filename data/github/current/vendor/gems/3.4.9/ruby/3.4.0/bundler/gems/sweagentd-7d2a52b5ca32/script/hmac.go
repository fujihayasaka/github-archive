// Script to generate a valid hmac request header value
package main

import (
	"fmt"
	"os"

	auth "github.com/github/go-auth/hmac"
)

func main() {
	secret := os.Getenv("APP_HMAC_KEY_0")
	if secret == "" {
		secret = "ghdevhmac"
	}
	hmac := auth.NewRequestHMAC(secret).String()
	fmt.Println(hmac)
}
