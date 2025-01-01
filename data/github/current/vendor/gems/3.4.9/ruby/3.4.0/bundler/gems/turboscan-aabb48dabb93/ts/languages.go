package ts

import (
	"database/sql/driver"
	"encoding/json"
	"sort"
	"strings"

	"github.com/pkg/errors"
)

// Languages represents an array of programming languages used
// to define managed analyses configurations.
type Languages []string

// NormalizeLanguages the list of languages
func NormalizeLanguages(langs Languages) Languages {
	out := make(Languages, len(langs))
	for idx, l := range langs {
		out[idx] = strings.ToLower(l)
	}
	sort.Strings(out)
	return out
}

func (e *Languages) Scan(val interface{}) error {
	switch v := val.(type) {
	case []byte:
		return json.Unmarshal(v, &e)
	case string:
		return json.Unmarshal([]byte(v), &e)
	default:
		return errors.Errorf("Unsupported type: %T", v)
	}
}

func (e Languages) string() (string, error) {
	if e == nil {
		e = Languages{}
	}
	v, err := json.Marshal(e)
	if err != nil {
		return "<invalid JSON>", err
	}
	return string(v), nil
}

func (e Languages) Value() (driver.Value, error) {
	return e.string()
}

func (e Languages) Valid() error {
	_, err := e.string()
	return err
}

func (e Languages) String() string {
	s, err := e.string()
	if err != nil {
		return "<invalid JSON>"
	}
	return s
}

func (e Languages) Equals(other Languages) bool {
	if len(e) != len(other) {
		return false
	}
	sort.Strings(other)
	for idx, l := range e {
		if l != other[idx] {
			return false
		}
	}
	return true
}
