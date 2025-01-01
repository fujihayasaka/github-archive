package http

import (
	"net/http"
	"strings"
)

// Return a new file server that does not permit directory listings. The default
// file server permits directory listings if the path ends in "/".
func NonListingFileServer(root string) http.HandlerFunc {
	server := http.FileServer(http.Dir(root))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/") {
			http.NotFound(w, r)
			return
		}
		server.ServeHTTP(w, r)
	})
}
