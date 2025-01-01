package main

// Config represents the configuration for the gh-lite server.
type Config struct {
	MonolithTwirpAPIHmacKey string `config:",env=MONOLITH_TWIRP_API_HMAC_KEY,required"`
}
