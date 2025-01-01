package ts

import (
	"database/sql/driver"
	"encoding/json"

	"github.com/google/go-cmp/cmp"
	"github.com/pkg/errors"
)

type QuerySuite uint8

const (
	QuerySuite_DEFAULT QuerySuite = iota
	QuerySuite_EXTENDED
)

func (qs QuerySuite) QuerySuiteType() QuerySuiteType {
	switch qs {
	case QuerySuite_DEFAULT:
		return DefaultQuerySuiteType()
	case QuerySuite_EXTENDED:
		return ExtendedQuerySuiteType()
	default:
		return DefaultQuerySuiteType()
	}
}

// DefaultQuerySuiteType returns default query suite type
func DefaultQuerySuiteType() QuerySuiteType {
	return QuerySuiteType{
		"root": QuerySuite_DEFAULT,
	}
}

// ExtendedQuerySuiteType returns the extended query suite type
func ExtendedQuerySuiteType() QuerySuiteType {
	return QuerySuiteType{
		"root": QuerySuite_EXTENDED,
	}
}

// QuerySuiteType represents map of query suites per language used to define managed analyses configurations.
// The "root" key is used to define the default query suite type for the repository.
type QuerySuiteType map[string]QuerySuite

func (q QuerySuiteType) Root() QuerySuite {
	if k, ok := q["root"]; ok {
		return k
	}

	return QuerySuite_DEFAULT
}

func (q *QuerySuiteType) Scan(val interface{}) error {
	switch v := val.(type) {
	case []byte:
		return json.Unmarshal(v, &q)
	case string:
		return json.Unmarshal([]byte(v), &q)
	default:
		return errors.Errorf("Unsupported type: %T", v)
	}
}

func (q QuerySuiteType) string() (string, error) {
	if q == nil {
		q = QuerySuiteType{}
	}
	v, err := json.Marshal(q)
	if err != nil {
		return "<invalid JSON>", err
	}
	return string(v), nil
}

func (q QuerySuiteType) Value() (driver.Value, error) {
	return q.string()
}

func (q QuerySuiteType) Valid() error {
	_, err := q.string()
	return err
}

func (q QuerySuiteType) String() string {
	s, err := q.string()
	if err != nil {
		return "<invalid JSON>"
	}
	return s
}

func (q QuerySuiteType) Equals(other QuerySuiteType) bool {
	return cmp.Equal(q, other)
}

func (q QuerySuiteType) IsDefault() bool {
	return q.Root() == QuerySuite_DEFAULT
}

func (q QuerySuiteType) IsExtended() bool {
	return q.Root() == QuerySuite_EXTENDED
}
