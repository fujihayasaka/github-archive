// Package config contains configuration for email layout.
package config

// Config represents email layout configuration.
type Config struct {
	FromAddressName string `config:",env=FROM_ADDRESS_NAME"`
	SenderDomain    string `config:",env=SENDER_DOMAIN"`
}
