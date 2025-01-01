// This file is used to generate a new HMAC token for local development
package main

import (
	"fmt"
	"os"

	"github.com/github/go-auth/hmac"
	"github.com/github/licensify/internal/config"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		fmt.Printf("failed to load config: %v\n", err)
		os.Exit(1)
	}
	token := hmac.NewRequestHMAC(cfg.GetAllHmacKeys()[0])
	fmt.Println(token)
}
