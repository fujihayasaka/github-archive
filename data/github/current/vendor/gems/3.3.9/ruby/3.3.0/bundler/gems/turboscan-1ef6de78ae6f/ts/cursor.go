package ts

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"strings"

	"github.com/pkg/errors"
)

// Cursor represents a cursor for paginating resources.
// It is a map of string to string, where the key is the name of the field and the value is the serialized value.
type Cursor map[string]string

// EncodeCursor encodes a cursor as a string
func EncodeCursor(cursor Cursor) (string, error) {
	var buf bytes.Buffer
	encoder := base64.NewEncoder(base64.URLEncoding, &buf)
	err := json.NewEncoder(encoder).Encode(cursor)
	if err != nil {
		return "", err
	}
	err = encoder.Close()
	if err != nil {
		return "", err
	}
	return buf.String(), nil
}

// DecodeCursor decodes a cursor from a string
func DecodeCursor(cursorString string) (Cursor, error) {
	var cursor Cursor
	if cursorString == "" {
		return cursor, nil
	}
	err := json.NewDecoder(base64.NewDecoder(base64.URLEncoding, strings.NewReader(cursorString))).Decode(&cursor)
	return cursor, err
}

// ExpressionSort represents a sort expression for the objects of type T.
type ExpressionSort[T any] interface {
	Expression() string
	SerializedName() string
	SerializedValue(T) string
	DeserializeValue(string) (interface{}, error)
}

// CursorSort represents a cursor enabled sort.
type CursorSort[T any] struct {
	Expressions []ExpressionSort[T]
	Descending  bool
}

// SQLCursorFilter represents a single filter for a cursor
type SQLCursorFilter struct {
	Expression string
	Value      interface{}
}

// SQLCursorSupported is an interface for types that support cursor filtering
type SQLCursorSupported interface {
	SetCursorFilter(filter []SQLCursorFilter)
}

// BuildCursor builds a cursor from an expression sort and an object.
func (sort CursorSort[T]) BuildCursor(object T) Cursor {
	cursor := map[string]string{}
	for _, exp := range sort.Expressions {
		cursor[exp.SerializedName()] = exp.SerializedValue(object)
	}
	return cursor
}

// OrderBy builds an ORDER BY clause for a list of expression sorts.
func (sort CursorSort[T]) OrderBy() string {
	order := "ASC"
	if sort.Descending {
		order = "DESC"
	}
	var expressions []string
	for _, exp := range sort.Expressions {
		expressions = append(expressions, exp.Expression()+" "+order)
	}
	return strings.Join(expressions, ", ")
}

// FilterBy builds a list of filters for a cursor.
func (sort CursorSort[T]) FilterBy(cursor Cursor) ([]SQLCursorFilter, error) {
	comparator := ">"
	if sort.Descending {
		comparator = "<"
	}
	var filters []SQLCursorFilter
	for _, exp := range sort.Expressions {
		if value, ok := cursor[exp.SerializedName()]; ok {
			deserializedValue, err := exp.DeserializeValue(value)
			if err != nil {
				return nil, errors.Wrapf(err, "failed to deserialize cursor value for %s", exp.SerializedName())
			}
			filters = append(filters, SQLCursorFilter{
				Expression: exp.Expression() + " " + comparator + " ?",
				Value:      deserializedValue,
			})
		}
	}
	return filters, nil
}
