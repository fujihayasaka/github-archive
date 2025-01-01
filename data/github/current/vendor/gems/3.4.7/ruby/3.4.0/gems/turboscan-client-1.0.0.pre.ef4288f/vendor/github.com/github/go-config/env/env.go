// Package env implements an environment loader.
//
// Keys will be converted to SCREAMING_SNAKE_CASE before being looked up in
// the environment.
//
// If a Prefix option is given, the prefix will be uppercased and prepended to
// the key.
//
// For example:
//
//	e := env.New(env.Prefix("foo"))
//	e.Lookup("bar")  // Looks for FOO_BAR in the environment
package env

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/github/go-config/snakecaser"
)

// Loader is a Loader that looks values up from the environment.
type Loader struct {
	prefix     string
	snakeCaser func(string) string
}

// Lookup looks up the key in the environment. The key is converted to
// SCREAMING_SNAKE_CASE. If a prefix has been specified, it will be prepended
// to the key as PREFIX_KEY_NAME.
//
//nolint:gocritic // Go recommends naked returns
func (e Loader) Lookup(key string) (string, bool, error) {
	if key != strings.ToUpper(key) {
		key = e.nameToEnv(e.prefix, key)
	}
	val, ok := os.LookupEnv(key)
	return val, ok, nil
}

// Name returns the name of this loader.
func (Loader) Name() string {
	return "env"
}

// Explicit returns whether this loader needs to be specified in the field's.
// loader chain.
func (Loader) Explicit() bool {
	return false
}

// New creates an env loader.
func New(options ...func(*Loader)) *Loader {
	loader := &Loader{
		snakeCaser: snakecaser.Do,
	}
	for _, option := range options {
		option(loader)
	}
	return loader
}

// Prefix sets a prefix for env lookup.
func Prefix(prefix string) func(*Loader) {
	return func(e *Loader) {
		e.prefix = prefix
	}
}

// SnakeCaser sets the function to be used converting property names to SCREAMING_SNAKE_CASE.
func SnakeCaser(snakeCaser func(string) string) func(*Loader) {
	return func(e *Loader) {
		e.snakeCaser = snakeCaser
	}
}

func (e Loader) nameToEnv(prefix, name string) string {
	snakeName := e.snakeCaser(name)
	if len(prefix) > 0 {
		return strings.ToUpper(prefix) + "_" + snakeName
	}
	return snakeName
}

// MapLoader is an Environment Loader that collates several environment
// variables into a map[string]<something>.
//
// This loader must be explicitly specified in the field's loader chain, with a
// value that is a prefix of the environment variable names that contain the
// values for the map. For example,
//
//	type Config struct {
//	   HMACSecrets map[string][]string `config:",env-prefix=HMAC_KEYS_"`
//	}
//
// This would load the environment variables HMAC_KEYS_FOO="bar baz bat"
// HMAC_KEYS_BAR="quux" into the map as
//
//	map[string][]string{
//	  "foo": []string{"bar", "baz", "bat"},
//	  "bar": []string{"quux"},
//	}
//
// The suffix of the environment variables (after keyprefix) will
// be lowercased and used as the map key. The value of the environment variable
// will be parsed as normal using go-config's parser and must match the format
// for the map's element type.
type MapLoader struct{}

// Lookup returns a json encoded map of all environment variables that have the
// given prefix.
func (e MapLoader) Lookup(keyPrefix string) (val string, found bool, err error) {
	result := map[string]string{}
	for _, e := range os.Environ() {
		pair := strings.SplitN(e, "=", 2)
		if len(pair) != 2 {
			// Shouldn't ever happen, but if it does, don't let one bad
			// environment variable torpedo everything.
			continue
		}
		after, found := CutPrefix(pair[0], keyPrefix)
		if !found {
			continue
		}
		result[strings.ToLower(after)] = pair[1]
	}
	b, err := json.Marshal(result)
	if err != nil {
		// should be impossible
		return "", false, fmt.Errorf("failed to encode result to json: %w", err)
	}
	return string(b), true, nil
}

// Name returns the name of this loader.
func (MapLoader) Name() string {
	return "env-prefix"
}

// Explicit returns whether this loader needs to be specified in the field's.
// loader chain.
func (MapLoader) Explicit() bool {
	return true
}

// CutPrefix is copied from the standard library, since it was introduced in Go 1.20
// but we're supporting back to Go 1.13.
func CutPrefix(s, prefix string) (after string, found bool) {
	if !strings.HasPrefix(s, prefix) {
		return s, false
	}
	return s[len(prefix):], true
}
