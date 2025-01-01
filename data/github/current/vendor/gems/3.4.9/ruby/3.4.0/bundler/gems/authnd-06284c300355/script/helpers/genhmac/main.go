package main

import (
	"fmt"
	"os"

	"github.com/github/go-auth/hmac"
)

func main() {
	hmacKey := "octocat"
	if len(os.Args) > 1 {
		hmacKey = os.Args[1]
	}

	hmac := hmac.NewRequestHMAC(hmacKey)
	fmt.Println(hmac.String())
}
