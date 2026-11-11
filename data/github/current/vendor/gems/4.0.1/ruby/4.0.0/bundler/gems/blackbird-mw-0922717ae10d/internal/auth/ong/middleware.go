package ong

import (
	"context"
	"net/http"
	"strings"
)

// Return a handler that authenticates a request and then calls the next handler
// if authenticated.
func Auth(token string) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if username, ok := ValidateHMACSignature(r, token); !ok {
				w.WriteHeader(http.StatusUnauthorized)
			} else {
				username = strings.TrimSuffix(username, "@github.com")
				ctx := context.WithValue(r.Context(), ongUsernameContextKey{}, &usernameWrapper{username})
				next.ServeHTTP(w, r.WithContext(ctx))
			}
		})
	}
}

func UsernameOnly() func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			username := r.Header.Get(usernameHeader)
			if username != "" {
				username = strings.TrimSuffix(username, "@github.com")
				ctx := context.WithValue(r.Context(), ongUsernameContextKey{}, &usernameWrapper{username})
				next.ServeHTTP(w, r.WithContext(ctx))
			} else {
				next.ServeHTTP(w, r)
			}
		})
	}
}

type ongUsernameContextKey struct{}

type usernameWrapper struct {
	username string
}

func GetUsername(ctx context.Context) string {
	val, ok := ctx.Value(ongUsernameContextKey{}).(*usernameWrapper)
	if ok && val != nil {
		return val.username
	}
	return ""
}

func SetUsername(ctx context.Context, username string) context.Context {
	return context.WithValue(ctx, ongUsernameContextKey{}, &usernameWrapper{username})
}
