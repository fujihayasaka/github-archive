package zuora

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"

	"github.com/pkg/errors"
)

type UsageServiceInterface interface {
	UploadUsage(usageRecords []UploadUsageRecord) (*UploadUsageResponse, error)
	GetUsageSummaries(uploadStart ZuoraUsageDateTime, uploadEnd ZuoraUsageDateTime) (*GetUsageSummariesResponse, error)
	GetUsageAggregate(request GetUsageAggregateRequest, options GetUsageAggregateOptions) (*GetUsageAggregateResponse, error)
}

type usageService struct {
	baseUrl    string
	httpClient http.Client
}

func newUsageService(httpClient http.Client, baseUrl string) UsageServiceInterface {
	return &usageService{
		baseUrl:    baseUrl,
		httpClient: httpClient,
	}
}

type UploadUsageRecord struct {
	CustomerId      string // Zuora account number (e.g. A00000098)
	UsageIdentifier string
	UsageDate       ZuoraUsageDateTime
	Amount          float64
	CostCenter      string
}

func (r UploadUsageRecord) Diff(other UploadUsageRecord) UploadUsageRecord {
	return UploadUsageRecord{
		CustomerId:      r.CustomerId,
		UsageIdentifier: r.UsageIdentifier,
		UsageDate:       r.UsageDate,
		Amount:          r.Amount - other.Amount,
		CostCenter:      r.CostCenter,
	}
}

type UploadUsageResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

func (s *usageService) UploadUsage(usageRecords []UploadUsageRecord) (*UploadUsageResponse, error) {
	url := fmt.Sprint(s.baseUrl, "/usage/bulk")

	jsonBody, err := json.Marshal(usageRecords)
	if err != nil {
		return nil, errors.Wrap(err, "error marshalling UploadUsage records")
	}

	req, err := http.NewRequest(http.MethodPost, url, bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, errors.Wrap(err, "error creating UploadUsage request")
	}
	req.Header.Add("Content-Type", "application/json")
	resp, err := s.httpClient.Do(req)

	if err != nil {
		return nil, errors.Wrap(err, "error making UploadUsage request")
	}

	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)

	if err != nil {
		return nil, errors.Wrap(err, "error reading UploadUsage response body")
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status code: %d, error uploading usage: %v", resp.StatusCode, string(body))
	}

	jsonResponse := &UploadUsageResponse{}

	if err := json.Unmarshal(body, &jsonResponse); err != nil {
		return nil, errors.Wrap(err, "error unmarshalling UploadUsage response")
	}

	if !jsonResponse.Success {
		return nil, fmt.Errorf("upload not successful : %v", string(body))
	}

	return jsonResponse, nil
}

type GetUsageSummariesResponse struct {
	Success bool         `json:"success"`
	Result  UsageSummary `json:"result"`
}
type UsageSummary struct {
	IngestionCount       int64         `json:"ingestionCount"`
	AggregationCount     int64         `json:"aggregationCount"`
	TransformFailedCount int64         `json:"transformFailedCount"`
	ErrorDetails         []ErrorDetail `json:"errorDetails"`
}

type ErrorDetail struct {
	ErrorCode string `json:"errorCode"`
	Count     int64  `json:"count"`
}

func (s *usageService) GetUsageSummaries(uploadStart ZuoraUsageDateTime, uploadEnd ZuoraUsageDateTime) (*GetUsageSummariesResponse, error) {
	url := fmt.Sprint(s.baseUrl, "/usage/summaries")

	req, err := http.NewRequest(http.MethodGet, url, nil)

	if err != nil {
		return nil, errors.Wrap(err, "error creating GetUsageSummaries request")
	}

	query := req.URL.Query()
	query.Add("uploadStart", uploadStart.Format(dateTimeFormat))
	query.Add("uploadEnd", uploadEnd.Format(dateTimeFormat))
	req.URL.RawQuery = query.Encode()

	req.Header.Add("Content-Type", "application/json")

	resp, err := s.httpClient.Do(req)

	if err != nil {
		return nil, errors.Wrap(err, "error making GetUsageSummaries request")
	}

	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)

	if err != nil {
		return nil, errors.Wrap(err, "error reading GetUsageSummaries response body")
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status code: %d, error getting usage summaries: %v", resp.StatusCode, string(body))
	}

	jsonResponse := &GetUsageSummariesResponse{}

	if err := json.Unmarshal(body, &jsonResponse); err != nil {
		return nil, errors.Wrap(err, "error unmarshalling GetUsageSummaries response")
	}

	return jsonResponse, nil
}

type GetUsageAggregateRequest struct {
	AccountNumbers []string `json:"accountNumbers"`
}
type GetUsageAggregateOptions struct {
	StartDateFrom ZuoraUsageDate // billing period start date inclusive
	StartDateTo   ZuoraUsageDate // billing period end date exclusive (pass +1 day to include the desired end date)
	Daily         bool           // if true, return a record in UsageAggregateResult.Items for each day
	AccountOnly   bool           // if true, return only the AccountNumber (SubscriptionNumber, ChargeNumber and Uom will be empty)
	Status        string         // "Pending" or "Billed"
}

type GetUsageAggregateResponse struct {
	Success bool                   `json:"success"`
	Result  []UsageAggregateResult `json:"result"`
}
type UsageAggregateResult struct {
	AccountNumber      string                     `json:"accountNumber"`
	SubscriptionNumber string                     `json:"subscriptionNumber,omitempty"`
	ChargeNumber       string                     `json:"chargeNumber,omitempty"`
	Uom                string                     `json:"uom,omitempty"`
	Quantity           float64                    `json:"quantity,string"`
	Items              []UsageAggregateResultItem `json:"items,omitempty"`
}
type UsageAggregateResultItem struct {
	Quantity   float64        `json:"quantity,string"`
	StartDate  ZuoraUsageDate `json:"startDate"`
	CostCenter string         `json:"CostCenter"`
}

func (s *usageService) GetUsageAggregate(request GetUsageAggregateRequest, options GetUsageAggregateOptions) (*GetUsageAggregateResponse, error) {
	url := fmt.Sprint(s.baseUrl, "/usage/aggregate")

	jsonBody, err := json.Marshal(request)
	if err != nil {
		return nil, errors.Wrap(err, "error marshalling GetUsageAggregateRequest")
	}

	req, err := http.NewRequest(http.MethodPost, url, bytes.NewBuffer(jsonBody))

	if err != nil {
		return nil, errors.Wrap(err, "error creating GetUsageAggregate request")
	}

	query := req.URL.Query()
	query.Add("startDateFrom", options.StartDateFrom.Format(dateFormat))
	query.Add("startDateTo", options.StartDateTo.Format(dateFormat))
	query.Add("daily", strconv.FormatBool(options.Daily))
	query.Add("accountOnly", strconv.FormatBool(options.AccountOnly))
	query.Add("status", options.Status)
	req.URL.RawQuery = query.Encode()

	req.Header.Add("Content-Type", "application/json")

	resp, err := s.httpClient.Do(req)

	if err != nil {
		return nil, errors.Wrap(err, "error making GetUsageAggregate request")
	}

	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)

	if err != nil {
		return nil, errors.Wrap(err, "error reading GetUsageAggregate response body")
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status code: %d, error getting usage aggregate: %v", resp.StatusCode, string(body))
	}

	jsonResponse := &GetUsageAggregateResponse{}

	if err := json.Unmarshal(body, &jsonResponse); err != nil {
		return nil, errors.Wrap(err, "error unmarshalling GetUsageAggregate response")
	}

	return jsonResponse, nil
}
