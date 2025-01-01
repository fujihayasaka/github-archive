package dsn

import (
	"fmt"
	"net/url"
	"strings"
)

func WithAttribute(str string, key string, value string) (string, error) {
	var base = str
	var attributes = make(url.Values)

	indexOfLastQuestionMark := strings.LastIndex(str, "?")

	if indexOfLastQuestionMark != -1 {
		base = str[:indexOfLastQuestionMark]
		vals, err := url.ParseQuery(str[indexOfLastQuestionMark+1:])
		if err != nil {
			return "", err
		}
		attributes = vals
	}

	attributes.Set(key, value)

	return fmt.Sprintf("%s?%s", base, attributes.Encode()), nil
}

func WithInterpolateParams(str string, value string) (string, error) {
	return WithAttribute(str, "interpolateParams", value)
}

func WithLoc(str string, value string) (string, error) {
	return WithAttribute(str, "loc", value)
}

// WithMigrationsTable overrides which migration table is used for schema
// migrations.
func WithMigrationsTable(str string, table string) (string, error) {
	return WithAttribute(str, "x-migrations-table", table)
}

// WithMultiStatementsEnabled sets multiStatements to true.
func WithMultiStatementsEnabled(str string) (string, error) {
	return WithAttribute(str, "multiStatements", "true")
}

// WithTimezone is an alias for WithLoc
func WithTimezone(str string, value string) (string, error) {
	return WithLoc(str, value)
}

func WithCharset(str string, value string) (string, error) {
	return WithAttribute(str, "charset", value)
}

func WithCollation(str string, value string) (string, error) {
	return WithAttribute(str, "collation", value)
}
