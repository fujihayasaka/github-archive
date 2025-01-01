package apiservice

import "time"

// Config represents the configuration for the API service.
type Config struct {
	// HmacKeys supports whitespace separated keys, for rotations.
	HmacKeys string        `config:",env=TWIRP_API_HMAC_KEYS,required"`
	Addr     string        `config:":8080,env=NOTIFYD_API_ADDR"`
	Timeout  time.Duration `config:"5s,env=NOTIFYD_API_TIMEOUT"`
}
