package db

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/onsi/gomega"
)

func Test_GetItemResponseLoggerFields(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	itemResponse := azcosmos.ItemResponse{
		Response: azcosmos.Response{
			RequestCharge: 5.0,
			RawResponse: &http.Response{
				StatusCode: 201,
			},
		},
	}

	fields := GetItemResponseLoggerFields(itemResponse, 0, nil)

	g.Expect(fields).To(gomega.Equal([]kvp.Field{
		kvp.Float32("db.cosmosdb.request_charge", 5.0),
		kvp.Int("db.status_code", 201),
	}))

	fields = GetItemResponseLoggerFields(itemResponse, 150*time.Millisecond, nil)

	g.Expect(fields).To(gomega.Equal([]kvp.Field{
		kvp.Float32("db.cosmosdb.request_charge", 5.0),
		kvp.Int64("db.cosmosdb.time_elapsed", 150),
		kvp.Int("db.status_code", 201),
	}))

	// error status codes should take precendence over the status code from the item response
	fields = GetItemResponseLoggerFields(itemResponse, 150*time.Millisecond, NewResponseError("RateLimit", 429))

	g.Expect(fields).To(gomega.Equal([]kvp.Field{
		kvp.Float32("db.cosmosdb.request_charge", 5.0),
		kvp.Int64("db.cosmosdb.time_elapsed", 150),
		kvp.Int("db.status_code", 429),
	}))
}

func Test_GetErrorStatusCode(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	// create an error response from cosmos
	err := NewResponseError("RateLimit", 429)

	// Test that a non-azcosmos error returns 0
	g.Expect(GetErrorStatusCode(err)).To(gomega.Equal(429))
}

func NewResponseError(errorCode string, statusCode int) *azcore.ResponseError {
	w := httptest.NewRecorder()
	w.WriteHeader(statusCode)
	response := w.Result()
	response.Request = httptest.NewRequest("GET", "http://mockme.com", nil)
	defer response.Body.Close()

	return &azcore.ResponseError{
		ErrorCode:   errorCode,
		StatusCode:  statusCode,
		RawResponse: response,
	}
}
