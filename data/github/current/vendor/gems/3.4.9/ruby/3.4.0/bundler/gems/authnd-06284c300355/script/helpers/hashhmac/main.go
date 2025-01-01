package main

import (
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("expected a hmac key to be provided")
		os.Exit(1)
	}
	key := os.Args[1]

	hash := sha256.New().Sum([]byte(key))
	encodedHash := base64.StdEncoding.EncodeToString(hash)

	end := 20
	if len(encodedHash) < end {
		end = len(encodedHash)
	}
	fmt.Println(encodedHash[0:end])
}
