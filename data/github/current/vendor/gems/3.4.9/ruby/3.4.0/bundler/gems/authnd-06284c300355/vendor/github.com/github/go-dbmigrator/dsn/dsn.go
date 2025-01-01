// Package dsn (data source name) provides utilities for working with database connection strings.
package dsn

import (
	"fmt"
	"net/url"
	"strings"
)

// WithAttribute adds an attribute to a connection string.
func WithAttribute(str, key, value string) (string, error) {
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

// WithInterpolateParams adds interpolateParams to a connection string.
func WithInterpolateParams(str, value string) (string, error) {
	return WithAttribute(str, "interpolateParams", value)
}

// WithLoc adds a loc to a connection string.
func WithLoc(str, value string) (string, error) {
	return WithAttribute(str, "loc", value)
}

// WithMigrationsTable overrides which migration table is used for schema
// migrations.
func WithMigrationsTable(str, table string) (string, error) {
	return WithAttribute(str, "x-migrations-table", table)
}

// WithMultiStatementsEnabled sets multiStatements to true.
func WithMultiStatementsEnabled(str string) (string, error) {
	return WithAttribute(str, "multiStatements", "true")
}

// WithTimezone is an alias for WithLoc.
func WithTimezone(str, value string) (string, error) {
	return WithLoc(str, value)
}

// WithCharset adds a charset to a connection string.
func WithCharset(str, value string) (string, error) {
	return WithAttribute(str, "charset", value)
}

// WithCollation adds a collation to a connection string.
func WithCollation(str, value string) (string, error) {
	return WithAttribute(str, "collation", value)
}
