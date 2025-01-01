package main

import (
	"fmt"

	"github.com/github/go-auth/hmac"
)

func main() {
	fmt.Println("Generating Request-HMAC header value")

	// uses default key set by config
	fmt.Println(hmac.NewRequestHMAC("billing-platform"))
}
