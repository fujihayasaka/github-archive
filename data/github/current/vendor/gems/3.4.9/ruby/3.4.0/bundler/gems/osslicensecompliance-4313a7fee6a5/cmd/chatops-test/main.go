// This is client code to test chatops service.
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	chatops "github.com/github/go-chatops/v2"
)

const requestTimeout = 30 * time.Second

func main() {
	key, err := chatops.ReadPEMPrivateKey(chatops.HubotTestPrivateKey)
	if err != nil {
		log.Fatal(err)
	}
	client := chatops.NewClientWithKey("http://localhost:8008/_chatops", key).
		WithOptions(chatops.ClientOptions{
			RequestTimeout: requestTimeout,
			AuthToken:      "test",
		})

	fmt.Println()
	//nolint:bodyclose // bodyclose is not applicable to chatops response.
	resp1, status1, err1 := client.Run("ping", os.Getenv("USER"), "testing-channel", map[string]string{})
	if err1 != nil {
		log.Fatal(err1)
	}
	if status1.StatusCode == http.StatusOK {
		fmt.Println("Chatops ping command succeeded!")
	} else {
		fmt.Println("Chatops ping command failed.")
	}
	fmt.Printf("%+v\n", resp1)

	fmt.Println()
	//nolint:bodyclose // bodyclose is not applicable to chatops response.
	resp2, status2, err2 := client.Run("hmac", os.Getenv("USER"), "testing-channel", map[string]string{})
	if err2 != nil {
		log.Fatal(err2)
	}
	if status2.StatusCode == http.StatusOK {
		fmt.Println("Chatops hmac command succeeded!")
	} else {
		fmt.Println("Chatops hmac command failed.")
	}
	fmt.Printf("%+v\n", resp2)
}
