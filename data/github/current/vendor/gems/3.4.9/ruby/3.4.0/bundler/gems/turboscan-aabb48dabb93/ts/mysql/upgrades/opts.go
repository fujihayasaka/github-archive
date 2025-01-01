package upgrades

import "time"

// Opts is a collection of options that apply to the Building (and subsequent
// execution) of a SQLTransition. These options are intended for interactive use
// to override the default behaviour. If a particular transition type does not
// respect one of these options, then its Build method should return an error if
// that option has a non-zero value.
type Opts struct {
	MinID   uint64
	MaxID   uint64
	Delay   time.Duration
	Step    uint64
	Timeout time.Duration // Timeout is the maximum duration a transition can run before giving up
}
