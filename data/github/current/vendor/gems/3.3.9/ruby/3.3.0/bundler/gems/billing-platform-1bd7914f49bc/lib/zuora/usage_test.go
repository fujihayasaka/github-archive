package zuora

import (
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"
	"time"

	"github.com/github/billing-platform/testing/stubs"
)

func setupMockServer(mockResponses []func(rw http.ResponseWriter, r *http.Request)) (*httptest.Server, *Client) {
	mockServer := stubs.SetupZuoraServer(mockResponses)

	zuoraClient := NewClient(mockServer.URL, "test_client_id", "test_client_secret")

	return mockServer, zuoraClient
}

func Test_UploadUsage_Successful_Request(t *testing.T) {
	mockResponses := []func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			rw.WriteHeader(200)
			_, _ = rw.Write([]byte(`{
				"success": true,
				"message": "Successfully uploaded 1 record"
			}`))
		},
	}
	mockServer, zuoraClient := setupMockServer(mockResponses)
	defer mockServer.Close()

	uploadRequest := []UploadUsageRecord{
		{
			CustomerId:      "A000000",
			UsageIdentifier: "Actions",
			UsageDate:       ZuoraUsageDateTime{Time: time.Now()},
			Amount:          10,
			CostCenter:      "Test",
		},
	}
	resp, err := zuoraClient.UsageService.UploadUsage(uploadRequest)

	if err != nil {
		t.Errorf("expected no error, got %s", err)
	}

	expected := UploadUsageResponse{
		Success: true,
		Message: "Successfully uploaded 1 record",
	}
	if !reflect.DeepEqual(*resp, expected) {
		t.Errorf("expected response to be %v, got %v", expected, resp)
	}
}

func Test_UploadUsage_Returns_Err_When_Request_Fails(t *testing.T) {
	mockResponses := []func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			rw.WriteHeader(400)
			_, _ = rw.Write([]byte(`{"success":false}`))
		},
	}

	mockServer, zuoraClient := setupMockServer(mockResponses)
	defer mockServer.Close()

	uploadRequest := []UploadUsageRecord{
		{
			CustomerId:      "A0000000",
			UsageIdentifier: "Actions",
			UsageDate:       ZuoraUsageDateTime{Time: time.Now()},
			Amount:          10,
			CostCenter:      "Test",
		},
	}
	_, err := zuoraClient.UsageService.UploadUsage(uploadRequest)

	expected := "status code: 400, error uploading usage: {\"success\":false}"
	if err.Error() != expected {
		t.Errorf("expected error to be %s, got %s", expected, err)
	}
}

func Test_GetUsageSummaries_Successful_Request(t *testing.T) {
	mockResponses := []func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			rw.WriteHeader(200)
			_, _ = rw.Write([]byte(`{
				"success": true,
				"result": {
					"ingestionCount": 3,
					"aggregationCount": 2,
					"transformFailedCount": 1,
					"errorDetails": [
						{
							"errorCode": "70000000",
							"count": 2
						}
					]
				}
			}`))
		},
	}
	mockServer, zuoraClient := setupMockServer(mockResponses)
	defer mockServer.Close()

	resp, err := zuoraClient.UsageService.GetUsageSummaries(
		ZuoraUsageDateTime{Time: time.Now().Add(-48 * time.Hour)},
		ZuoraUsageDateTime{Time: time.Now()},
	)

	if err != nil {
		t.Errorf("expected no error, got %s", err)
	}

	expected := GetUsageSummariesResponse{
		Success: true,
		Result: UsageSummary{
			IngestionCount:       3,
			AggregationCount:     2,
			TransformFailedCount: 1,
			ErrorDetails: []ErrorDetail{
				{
					ErrorCode: "70000000",
					Count:     2,
				},
			},
		},
	}

	if !reflect.DeepEqual(*resp, expected) {
		t.Errorf("expected response to be %v, got %v", expected, resp)
	}
}

func Test_GetUsageSummary_Returns_Err_When_Request_Fails(t *testing.T) {
	mockResponses := []func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			rw.WriteHeader(400)
			_, _ = rw.Write([]byte(`{"success":false}`))
		},
	}

	mockServer, zuoraClient := setupMockServer(mockResponses)
	defer mockServer.Close()

	_, err := zuoraClient.UsageService.GetUsageSummaries(
		ZuoraUsageDateTime{Time: time.Now().Add(-48 * time.Hour)},
		ZuoraUsageDateTime{Time: time.Now()},
	)

	expected := "status code: 400, error getting usage summaries: {\"success\":false}"
	if err.Error() != expected {
		t.Errorf("expected error to be %s, got %s", expected, err)
	}
}

func Test_GetUsageAggregate_Successful_Request(t *testing.T) {
	mockResponses := []func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			expectedURI := "/usage/aggregate?accountOnly=true&daily=false&startDateFrom=2023-05-14&startDateTo=2023-05-16&status=Pending"
			if r.RequestURI != expectedURI {
				t.Errorf("expected request uri to be %s, got %s", expectedURI, r.RequestURI)
			}

			rw.WriteHeader(200)
			_, _ = rw.Write([]byte(`{
				"success": true,
				"result": [{
					"accountNumber": "A0000000",
					"quantity": "10.5"
				}]
			}`))
		},
	}
	mockServer, zuoraClient := setupMockServer(mockResponses)
	defer mockServer.Close()

	reqOpt := GetUsageAggregateOptions{
		StartDateFrom: ZuoraUsageDate{time.Date(2023, 5, 14, 0, 0, 0, 0, time.UTC)},
		StartDateTo:   ZuoraUsageDate{time.Date(2023, 5, 16, 0, 0, 0, 0, time.UTC)},
		Daily:         false,
		Status:        "Pending",
		AccountOnly:   true,
	}
	reqBody := GetUsageAggregateRequest{
		AccountNumbers: []string{"A0000000"},
	}
	resp, err := zuoraClient.UsageService.GetUsageAggregate(reqBody, reqOpt)

	if err != nil {
		t.Errorf("expected no error, got %s", err)
	}
	expected := GetUsageAggregateResponse{
		Success: true,
		Result: []UsageAggregateResult{
			{
				AccountNumber: "A0000000",
				Quantity:      10.5,
			},
		},
	}

	if !reflect.DeepEqual(*resp, expected) {
		t.Errorf("expected response to be %v, got %v", expected, resp)
	}
}

func Test_GetUsageAggregate_Successful_Request_With_Extra_Fields(t *testing.T) {
	mockResponses := []func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			expectedURI := "/usage/aggregate?accountOnly=false&daily=true&startDateFrom=2023-05-14&startDateTo=2023-05-16&status=Pending"
			if r.RequestURI != expectedURI {
				t.Errorf("expected request uri to be %s, got %s", expectedURI, r.RequestURI)
			}

			rw.WriteHeader(200)
			_, _ = rw.Write([]byte(`{
				"success": true,
				"result": [{
					"accountNumber": "A0000000",
					"subscriptionNumber": "S000000",
					"chargeNumber": "C000000",
					"uom": "Each",
					"quantity": "10.5",
					"items": [{
						"quantity": "10.5",
						"startDate": "2023-01-23",
						"CostCenter": "Default"
					}]
				}]
			}`))
		},
	}
	mockServer, zuoraClient := setupMockServer(mockResponses)
	defer mockServer.Close()

	reqOpt := GetUsageAggregateOptions{
		StartDateFrom: ZuoraUsageDate{time.Date(2023, 5, 14, 0, 0, 0, 0, time.UTC)},
		StartDateTo:   ZuoraUsageDate{time.Date(2023, 5, 16, 0, 0, 0, 0, time.UTC)},
		Daily:         true,
		Status:        "Pending",
		AccountOnly:   false,
	}
	reqBody := GetUsageAggregateRequest{
		AccountNumbers: []string{"A0000000"},
	}
	resp, err := zuoraClient.UsageService.GetUsageAggregate(reqBody, reqOpt)

	if err != nil {
		t.Errorf("expected no error, got %s", err)
	}
	expected := GetUsageAggregateResponse{
		Success: true,
		Result: []UsageAggregateResult{
			{
				AccountNumber:      "A0000000",
				SubscriptionNumber: "S000000",
				ChargeNumber:       "C000000",
				Uom:                "Each",
				Quantity:           10.5,
				Items: []UsageAggregateResultItem{
					{
						Quantity:   10.5,
						StartDate:  ZuoraUsageDate{time.Date(2023, 1, 23, 0, 0, 0, 0, time.UTC)},
						CostCenter: "Default",
					},
				},
			},
		},
	}

	if !reflect.DeepEqual(*resp, expected) {
		t.Errorf("expected response to be %v, got %v", expected, resp)
	}
}

func Test_GetUsageAggregate_Returns_Err_When_Request_Fails(t *testing.T) {
	mockResponses := []func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			rw.WriteHeader(400)
			_, _ = rw.Write([]byte(`{"success":false}`))
		},
	}

	mockServer, zuoraClient := setupMockServer(mockResponses)
	defer mockServer.Close()

	reqOpt := GetUsageAggregateOptions{
		StartDateFrom: ZuoraUsageDate{time.Now().Add(-48 * time.Hour)},
		StartDateTo:   ZuoraUsageDate{time.Now()},
		Daily:         false,
		Status:        "Pending",
		AccountOnly:   true,
	}
	reqBody := GetUsageAggregateRequest{
		AccountNumbers: []string{"A0000000"},
	}
	_, err := zuoraClient.UsageService.GetUsageAggregate(reqBody, reqOpt)

	expected := "status code: 400, error getting usage aggregate: {\"success\":false}"
	if err.Error() != expected {
		t.Errorf("expected error to be %s, got %s", expected, err)
	}
}
