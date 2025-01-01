package twirp

import "errors"

// ErrMalformedEvent should be returned whenever an event with
// invalid or malformed data is detected.
var ErrMalformedEvent = errors.New("malformed event")
