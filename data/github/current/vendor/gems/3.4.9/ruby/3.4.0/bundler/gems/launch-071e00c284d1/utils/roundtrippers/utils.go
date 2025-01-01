package roundtrippers

import (
	"context"
	"net/http"
	"strings"

	"github.com/github/go-kvp"
	gokvp "github.com/github/go-kvp"

	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"
)

func cleanCtx(ctx context.Context) context.Context {
	ctx = ctxstash.WithEmptyStash(ctx)
	return context.WithValue(ctx, reqmeta.RMDContextKey, reqmeta.NewRequestMetadata())
}

func extractCorrelationRespHeaders(resp *http.Response) []gokvp.Field {
	fields := []gokvp.Field{}
	if respVSSID := resp.Header.Get(azpcorrelation.VSSE2EIDHeaderName); respVSSID != "" {
		fields = append(fields, gokvp.String(rlhRespVSSID, respVSSID))
	}
	return fields
}

func extractCorrelationFields(c ctxstash.Correlations) []gokvp.Field {
	var fields []gokvp.Field
	fields = appendIfNotEmpty(fields, rlhRequestID, c.GitHub.RequestID)
	fields = appendIfNotEmpty(fields, rlhAqueductJobID, c.Aqueduct.JobID)
	fields = appendIfNotEmpty(fields, rlhOrigAqueductJobID, c.Aqueduct.OriginalJobID)
	fields = appendIfNotEmpty(fields, rlhOrchestrationID, c.VSS.OrchestrationID)
	fields = appendIfNotEmpty(fields, rlhReqVSSID, c.VSS.RequestE2EID)
	fields = appendIfNotEmpty(fields, rlhVSSID, c.VSS.CorrelationID)
	return fields
}

func appendIfNotEmpty(fields []gokvp.Field, key, value string) []kvp.Field {
	if value != "" {
		fields = append(fields, gokvp.String(key, value))
	}
	return fields
}

func prettyPrintStatusCode(code int) string {
	s := http.StatusText(code)
	return strings.ReplaceAll(strings.ToLower(s), " ", "_")
}
