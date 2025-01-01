// Package config provides a way to fill in a configuration struct from the
// environment and other loaders. Currently supported loaders are:
//   - config/env
//   - config/json
//   - config/vault
//
// Configuration begins with a struct whose exported fields can be tagged with
// `config`. When loading the values into this struct the tagged field names are
// passed to a chain of loaders that attempt to look up values for the field.
// Fields not tagged with `config` are ignored by this package.
//
// Tagged fields must have an underlying type of string, []string, bool, or an
// integer or floating-point number; one of the special types time.Duration,
// Byte, or rsa.{Private,PublicKey}; or a type T that defines a (*T).Set method,
// or a map[string]T where T is one of the previous mentioned types.
//
// If no loaders are given, the values will be pulled from the environment by
// converting the field names to SCREAMING_SNAKE_CASE for look up.
//
// Unless an env loader is explicitly placed in the chain, a non-prefixed env
// loader will always be consulted first. A env.MapLoader will be consulted
// second, and then proceeding through the chain until the key is located.
//
// Loaders in the load chain are searched in the order given.
//
// The "config" key in the struct field's tag value is the default value given
// to the field, followed by an optional comma and options.
//
// Examples:
//
//	// Field is will be looked up in the load chain. If not found, it will
//	// be given the zero value for its type.
//	Field string `config:""`
//
//	// Field is given the default value "foo" if not found in the load chain.
//	Field string `config:"foo"`
//
//	// Field is required and `Load()` will return an error if it is not
//	// found in the load chain.
//	Field string `config:",required"`
//
//	// Field will load from vault if it is not found in env. Vault is an
//	// example of an explicit loader, meaning to load from vault it must be
//	// included in the tag, it will not be part of the default load chain.
//	Field string `config:"foo,vault"
//
//	// Tags can specify their own load chain. Here field will be looked up
//	// in vault first, then fall back to the env lookup.
//	Field string `config:",vault,env"
//
//	// A lookup key can be given explicitly in the tag, avoiding trying to
//	// calculate one from the field name. Here field will be looked up in
//	// the env loader with the key FOO instead of FIELD.
//	Field string `config:",env=foo"`
//
//	// Maps are extracted from the environment by specifying a prefix for the
//	// environment variable names. The prefix is stripped from the environment
//	// variable name and the remainder is lowercased and used as the key in the
//	// map.
//	Field map[string][]string `config:",env-prefix=HMAC_SECRETS_"`
//
// Loaders are responsible for determining the key name from the field name.
//
// A load chain example:
//
//	jsonLoader, _ := json.New("config.json")
//	config.Load(cfg, env.New(env.Prefix("APP")), jsonLoader, vault.New("secret/app"))
//
// The code above specifies:
//   - an env loader that will prefix key names with APP_
//   - a json loader that will load keys from the `config.json` file
//   - a vault loader that will look up keys under the `secret/app` path.
//
// An app can specify their own loader by conforming to the `config.Loader`
// interface.
//
// This package will convert the values to their proper numeric and boolean
// types, according to the struct field's type.
//
// An example of a configuration struct:
//
//	type Config struct {
//	    Name string                     `config:"my_app"`
//	    Host string                     `config:"localhost"`
//	    Port int                        `config:"9090"`
//	    AutoStart bool                  `config:"false"`
//	    ClientIDs []string              `config:"s3cr3t1 s3cr3t2"`
//	    HMACSecrets map[string][]string `config:",env-prefix=HMAC_SECRETS_"
//	}
//
// On loading, the config will be loaded from the env using the following keys:
//
//	NAME, HOST, PORT, AUTO_START, CLIENT_IDS, and any environment variable that starts with HMAC_SECRETS_
package config
