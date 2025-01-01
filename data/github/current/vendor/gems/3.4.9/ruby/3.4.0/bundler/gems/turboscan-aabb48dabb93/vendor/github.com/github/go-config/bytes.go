package config

import (
	"errors"
	"fmt"
)

type Byte int64

var errLeadingInt = errors.New("bytes: bad [0-9]*") // never printed

// leadingInt consumes the leading [0-9]* from s.
func leadingInt(s string) (x int64, rem string, err error) {
	// This code is a direct copy of leadingInt from
	// https://github.com/golang/go/blob/d70a33a4/src/time/format.go#L1307

	i := 0
	for ; i < len(s); i++ {
		c := s[i]
		if c < '0' || c > '9' {
			break
		}
		if x > (1<<63-1)/10 {
			// overflow
			return 0, "", errLeadingInt
		}
		x = x*10 + int64(c) - '0'
		if x < 0 {
			// overflow
			return 0, "", errLeadingInt
		}
	}
	return x, s[i:], nil
}

// leadingFraction consumes the leading [0-9]* from s.
// It is used only for fractions, so does not return an error on overflow,
// it just stops accumulating precision.
func leadingFraction(s string) (x int64, scale float64, rem string) {
	// This code is a direct copy of leadingFraction from
	// https://github.com/golang/go/blob/d70a33a4/src/time/format.go#L1330

	i := 0
	scale = 1
	overflow := false
	for ; i < len(s); i++ {
		c := s[i]
		if c < '0' || c > '9' {
			break
		}
		if overflow {
			continue
		}
		if x > (1<<63-1)/10 {
			// It's possible for overflow to give a positive number, so take care.
			overflow = true
			continue
		}
		y := x*10 + int64(c) - '0'
		if y < 0 {
			overflow = true
			continue
		}
		x = y
		scale *= 10
	}
	return x, scale, s[i:]
}

// Base-2 byte units.
const (
	Kibibyte Byte = 1024
	Mebibyte      = Kibibyte * 1024
	Gibibyte      = Mebibyte * 1024
	Tebibyte      = Gibibyte * 1024
)

// SI base-10 byte units.
const (
	Kilobyte Byte = 1000
	Megabyte      = Kilobyte * 1000
	Gigabyte      = Megabyte * 1000
	Terabyte      = Gigabyte * 1000
)

var unitMap = map[string]int64{
	"TB":  int64(Terabyte),
	"TiB": int64(Tebibyte),
	"GB":  int64(Gigabyte),
	"GiB": int64(Gibibyte),
	"MB":  int64(Megabyte),
	"MiB": int64(Mebibyte),
	"KB":  int64(Kilobyte),
	"KiB": int64(Kibibyte),
	"B":   1,
}

// ParseBytes parses a string into a number of bytes
// A bytes string is a sequence of
// integer numbers, each with a unit suffix,
// such as "300MiB" or "10GB5MB" or "1.5KiB".
// Valid units are:
//   - SI units
//   - "TB": 10^12 bytes
//   - "GB": 10^9 bytes
//   - "MB": 10^6 bytes
//   - "KB": 10^3 bytes
//   - "B": 1 byte
//   - binary units:
//   - "TiB": 2^40 bytes
//   - "GiB": 2^30 bytes
//   - "MiB": 2^20 bytes
//   - "KiB": 2^10 bytes
func ParseBytes(s string) (Byte, error) {
	// This code is a direct copy of ParseDuration from
	// https://github.com/golang/go/blob/d70a33a4/src/time/format.go#L1374

	// [-+]?([0-9]*(\.[0-9]*)?[a-z]+)+
	orig := s
	var d int64
	neg := false

	// Consume [-+]?
	if s != "" {
		c := s[0]
		if c == '-' || c == '+' {
			neg = c == '-'
			s = s[1:]
		}
	}
	// Special case: if all that is left is "0", this is zero.
	if s == "0" {
		return 0, nil
	}
	if s == "" {
		return 0, fmt.Errorf("invalid bytes %q", orig)
	}
	for s != "" {
		var (
			// integers before, after decimal point.
			v, f int64
			// value = v + f/scale.
			scale float64 = 1
		)

		var err error

		// The next character must be [0-9.]
		if !(s[0] == '.' || '0' <= s[0] && s[0] <= '9') {
			return 0, fmt.Errorf("invalid bytes %q", orig)
		}
		// Consume [0-9]*
		pl := len(s)
		v, s, err = leadingInt(s)
		if err != nil {
			return 0, fmt.Errorf("invalid bytes %q", orig)
		}
		pre := pl != len(s) // whether we consumed anything before a period

		// Consume (\.[0-9]*)?
		post := false
		if s != "" && s[0] == '.' {
			s = s[1:]
			pl := len(s)
			f, scale, s = leadingFraction(s)
			post = pl != len(s)
		}
		if !pre && !post {
			// no digits (e.g. ".s" or "-.s")
			return 0, fmt.Errorf("invalid bytes %q", orig)
		}

		// Consume unit.
		i := 0
		for ; i < len(s); i++ {
			c := s[i]
			if c == '.' || '0' <= c && c <= '9' {
				break
			}
		}
		if i == 0 {
			return 0, fmt.Errorf("missing unit in bytes %q", orig)
		}
		u := s[:i]
		s = s[i:]
		unit, ok := unitMap[u]
		if !ok {
			return 0, fmt.Errorf("unknown unit %q in bytes %q", u, orig)
		}
		if v > (1<<63-1)/unit {
			// overflow
			return 0, fmt.Errorf("invalid bytes %q", orig)
		}
		v *= unit
		if f > 0 {
			// v >= 0 && (f*unit/scale) <= 3.6e+12 (ns/h, h is the largest unit)
			v += int64(float64(f) * (float64(unit) / scale))
			if v < 0 {
				// overflow
				return 0, fmt.Errorf("invalid bytes %q", orig)
			}
		}
		d += v
		if d < 0 {
			// overflow
			return 0, fmt.Errorf("invalid bytes %q", orig)
		}
	}

	if neg {
		d = -d
	}
	return Byte(d), nil
}
