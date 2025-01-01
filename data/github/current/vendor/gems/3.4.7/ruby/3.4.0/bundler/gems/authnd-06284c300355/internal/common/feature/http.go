package feature

import (
	"encoding/base64"
	"encoding/json"
	"net/http"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
)

const HeaderName = "X-GitHub-Features"

// Handler is a middleware that adds any features encoded in the 'X-GitHub-Features' header
// to the request context.
func Handler(next http.Handler) http.Handler {
	fn := func(w http.ResponseWriter, r *http.Request) {
		logger := diagnostics.Logger(r.Context())

		features := featuresForRequest(r)
		if len(features) > 0 {
			logger.Info("features enabled for request", kvp.Any("gh.authnd.request.features", features))
			r = r.WithContext(NewContext(r.Context(), features))
		}

		next.ServeHTTP(w, r)
	}
	return http.HandlerFunc(fn)
}

func featuresForRequest(r *http.Request) map[string]bool {
	logger := diagnostics.Logger(r.Context())

	encoded := r.Header.Get(HeaderName)
	if encoded == "" {
		return nil
	}

	decodedBytes, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		logger.WithError(err).Info("failed to decode failpoints from header", kvp.String("gh.authnd.request.encoded_header", encoded))
		return nil
	}

	var featureList []string
	err = json.Unmarshal(decodedBytes, &featureList)
	if err != nil {
		logger.WithError(err).Info("failed to unmarshal failpoints from header", kvp.String("gh.authnd.request.decoded_header", string(decodedBytes)))
		return nil
	}
	features := make(map[string]bool, len(featureList))
	for _, feature := range featureList {
		features[feature] = true
	}
	return features
}
