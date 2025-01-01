package azp

import (
	"errors"
	"strconv"
	"time"
)

type BearerToken struct {
	AccessToken string `json:"access_token"`
	ExpiresIn   any    `json:"expires_in"`
}

// Expires handles the fact that different token endpoints return either int or string values
// in json (eg `..."expires_in": 3000...` vs `..."expires_in":"3000"...`).
func (t *BearerToken) Expires() (time.Duration, error) {
	switch v := t.ExpiresIn.(type) {
	case float64:
		// `v` is in seconds, so if it's 3.556 we'd want to get 3556ms, and not 3 or 4s.
		// so we need to scale the float64 up before making it a duration to avoid rounding off
		// too aggressively
		return time.Duration(v*1.0e6) * time.Microsecond, nil
	case string:
		val, err := strconv.Atoi(v)
		if err != nil {
			return 0, err
		}
		return time.Duration(val) * time.Second, nil
	default:
		return 0, errors.New("did not receive a string or int for token.expires_in")
	}
}
