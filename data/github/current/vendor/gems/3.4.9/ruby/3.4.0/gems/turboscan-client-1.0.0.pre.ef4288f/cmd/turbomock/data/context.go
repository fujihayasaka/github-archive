// Package data contains methods for loading cassettes
package data

import (
	"bytes"
	"context"
	"encoding/json"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/turbocassette/vcr"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"gopkg.in/yaml.v3"
)

type contextKey string

var requestPathKey contextKey = "RequestPath"
var cassettePathKey contextKey = "CassettePath"

func getCassettePath(ctx context.Context, name string) string {
	return filepath.Join(ctx.Value(cassettePathKey).(string), name)
}

// Mux wraps a http.Handler with the context required to load cassettes
func Mux(cassettePath string, next http.Handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		ctx = context.WithValue(ctx, requestPathKey, r.URL.Path)
		ctx = context.WithValue(ctx, cassettePathKey, cassettePath)
		next.ServeHTTP(w, r.WithContext(ctx))
	}
}

type pointerToMessage[T any] interface {
	*T
	proto.Message
}

// LoadCassette returns the first suitable response from the named cassette
func LoadCassette[T any, S pointerToMessage[T]](ctx context.Context, name string, msg S) (S, error) {
	if msg == nil {
		msg = new(T)
	}

	path, ok := ctx.Value(requestPathKey).(string)
	if !ok {
		return msg, errors.New("cannot LoadCassette without request path context")
	}

	cassettePath := getCassettePath(ctx, name)

	log.Print("📼 ", cassettePath)

	data, err := os.ReadFile(cassettePath)
	if err != nil {
		return msg, err
	}

	decoder := yaml.NewDecoder(bytes.NewReader(data))
	decoder.KnownFields(true)

	var tape vcr.Cassette
	if err := decoder.Decode(&tape); err != nil {
		return msg, err
	}

	for _, interaction := range tape.Interactions {
		uri, err := url.Parse(interaction.Request.URI)
		if err != nil {
			return msg, err
		}

		if uri.Path != path {
			continue
		}

		if interaction.Response.Status.Code != http.StatusOK {
			continue
		}

		err = protojson.Unmarshal(json.RawMessage(interaction.Response.Body.String), msg)
		if err != nil && strings.Contains(err.Error(), "unknown field") {
			return msg, errors.Errorf("%v: if your protobuf definition has changed, try rebuilding turbomock", err)
		}

		return msg, err
	}

	return msg, errors.New("cassette not matched")
}
