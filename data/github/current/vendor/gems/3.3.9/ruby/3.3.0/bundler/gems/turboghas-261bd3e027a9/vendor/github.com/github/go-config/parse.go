package config

import (
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"reflect"
	"strconv"
	"strings"
	"time"
)

// A Setter is a type that defines its own config parsing function.
type Setter interface {
	Set(val string) error
}

// parse parses the value string and sets the variable referred to by
// the (addressable) reflect.Value. It returns an error if val does
// not denote a suitable value for the variable.
func parse(val string, field reflect.Value) error {
	t := field.Type()

	// Custom parsing behavior for fields with a (*T).Set method.
	if field.CanAddr() {
		if setter, ok := field.Addr().Interface().(Setter); ok {
			return setter.Set(val)
		}
	}

	// Handle special types.
	switch t {
	case reflect.TypeOf(time.Duration(0)): // time.Duration
		d, err := time.ParseDuration(val)
		if err != nil {
			return err
		}

		field.Set(reflect.ValueOf(d))
		return nil

	case reflect.TypeOf(Byte(0)): // Byte
		d, err := ParseBytes(val)
		if err != nil {
			return err
		}

		field.Set(reflect.ValueOf(d))
		return nil

	case reflect.TypeOf((*rsa.PrivateKey)(nil)): // *rsa.PrivateKey
		if val == "" {
			return nil
		}

		block, _ := pem.Decode([]byte(val))
		if block == nil {
			return errors.New("no private key found in data")
		}
		key, err := x509.ParsePKCS1PrivateKey(block.Bytes)
		if err != nil {
			return err
		}
		field.Set(reflect.ValueOf(key))
		return nil

	case reflect.TypeOf((*rsa.PublicKey)(nil)): // *rsa.PublicKey
		if val == "" {
			return nil
		}

		block, _ := pem.Decode([]byte(val))
		if block == nil {
			return errors.New("no public key found in data")
		}

		var rsaPubKey *rsa.PublicKey
		var err error
		if block.Type == "RSA PUBLIC KEY" {
			rsaPubKey, err = x509.ParsePKCS1PublicKey(block.Bytes)
			if err != nil {
				return err
			}
		} else {
			key, err := x509.ParsePKIXPublicKey(block.Bytes)
			if err != nil {
				return err
			}
			var ok bool
			rsaPubKey, ok = key.(*rsa.PublicKey)
			if !ok {
				return errors.New("public key was not rsa.PublicKey")
			}
		}

		field.Set(reflect.ValueOf(rsaPubKey))
		return nil

	case reflect.TypeOf([]string{}):
		stringArray := []string{}

		for _, rawString := range strings.Split(val, " ") {
			cleanString := strings.TrimSpace(rawString)

			// Note: Split will return some empty strings even if no
			// "real" elements are present. We want to ignore those.
			if cleanString == "" {
				continue
			}
			stringArray = append(stringArray, cleanString)
		}

		field.Set(reflect.ValueOf(stringArray))
		return nil
	}

	// Generic handling of all types whose underlying
	// representation is string, number, bool, or map.
	switch t.Kind() {
	case reflect.Bool:
		b, err := strconv.ParseBool(val)
		if err != nil {
			return err
		}

		field.SetBool(b)
		return nil

	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		n, err := strconv.ParseInt(val, 0, t.Bits())
		if err != nil {
			return err
		}
		field.SetInt(n)
		return nil

	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uintptr:
		n, err := strconv.ParseUint(val, 0, t.Bits())
		if err != nil {
			return err
		}

		field.SetUint(n)
		return nil

	case reflect.Float32, reflect.Float64:
		n, err := strconv.ParseFloat(val, t.Bits())
		if err != nil {
			return err
		}

		field.SetFloat(n)
		return nil

	case reflect.String:
		// A string value is used directly,
		// not treated as a literal.
		field.SetString(val)
		return nil

	case reflect.Map:
		// get the key and value type of the reflected map
		if t.Key().Kind() != reflect.String {
			return fmt.Errorf("map key type must be string, but was %v", t.Key().Kind())
		}

		// for a map, we expect the value to be a json encoded map[string]string.
		valmap := map[string]string{}
		err := json.Unmarshal([]byte(val), &valmap)
		if err != nil {
			return fmt.Errorf("value returned for map field is not a valid json map[string]string: %w", err)
		}

		m := reflect.MakeMap(t)
		for k, v := range valmap {
			// make a new value of the map's value type, so we can use parse to
			// set it.
			val := reflect.New(t.Elem()).Elem()
			err := parse(v, val)
			if err != nil {
				return fmt.Errorf("error parsing map value for key %q: %w", k, err)
			}
			// set the value in the map
			m.SetMapIndex(reflect.ValueOf(k), val)
		}
		field.Set(m)
		return nil
	}

	return fmt.Errorf("unsupported type %q", field.Type())
}
