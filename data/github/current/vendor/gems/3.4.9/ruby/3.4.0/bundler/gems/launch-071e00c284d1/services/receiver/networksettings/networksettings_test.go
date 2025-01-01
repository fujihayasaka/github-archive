package networksettings

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/auth"
	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/testutils"
)

var rawSignature = []byte("random_signature")
var bodyBytes = bytes.NewReader([]byte(""))

func TestNetworkSettings(t *testing.T) {
	suite.Run(t, new(NetworkSettingsTestSuite))
}

const (
	httpsScheme = "https"
)

type MockHTTPClient struct {
	Response *http.Response
	Err      error
	Url      *url.URL
}

func (m *MockHTTPClient) Do(req *http.Request) (*http.Response, error) {
	m.Url = req.URL
	return m.Response, m.Err
}

func (m *MockHTTPClient) RoundTrip(req *http.Request) (*http.Response, error) {
	m.Url = req.URL
	return m.Response, m.Err
}

type NetworkSettingsTestSuite struct {
	suite.Suite
	svc              *Service
	db               deployer.MockAzpResourcesLoader
	log              testutils.RecordingLogger
	verifier         *auth.MockVerifier
	tenantID         string
	runnerGroupID    string
	httpVerifier     *hmac.HTTPVerifier
	authVerifier     *auth.MockVerifier
	keyFetcher       *hmac.MockKeyFetcher
	httpClient       *http.Client
	twirpClient      *ghtwirp.MockClient
	responseRecorder *httptest.ResponseRecorder
	mockClient       *MockHTTPClient
	request          *http.Request
}

func (s *NetworkSettingsTestSuite) SetupTest() {
	s.tenantID = "test-tenant-id"
	s.runnerGroupID = "test-runner-group-id"
	s.authVerifier = &auth.MockVerifier{}
	s.keyFetcher = &hmac.MockKeyFetcher{}
	s.responseRecorder = httptest.NewRecorder()
	s.mockClient = &MockHTTPClient{
		Response: &http.Response{
			StatusCode: http.StatusForbidden,
		},
	}
	s.twirpClient = &ghtwirp.MockClient{}
	s.request = s.getHttpRequest("0")

	s.keyFetcher.On("GetHMACKeys", mock.Anything).Return([2]auth.Key{[]byte("hmacKey"), []byte("hmacKey")}, nil)
	obs := observability.New(testutils.NewRecordingLogger().Logger, statter.NullStatter())
	s.httpVerifier = hmac.NewHTTPVerifier(s.keyFetcher, obs, s.authVerifier, httpsScheme)
	url := "https://networkserviceurl.com"
	hmac_key := "sekrit"
	s.svc = NewService(
		obs,
		&s.db,
		s.httpVerifier,
		url,
		hmac_key,
		ahttp.NewRetryClient(
			nil,
			statter.NullStatter(),
			&http.Client{Transport: s.mockClient},
			"networkservice-test-client",
		),
		s.twirpClient,
	)
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	var enterpriseDbID int64 = 42
	var enterpriseGlobalID = types.GlobalID(testutils.EncodeGlobalID("Enterprise", enterpriseDbID))
	s.db.On("GetByTenantID", mock.Anything, mock.Anything).Return(&deployer.AzpResource{
		EntityID: enterpriseGlobalID,
		TenantID: s.tenantID,
	}, true, nil)
}

func (s *NetworkSettingsTestSuite) getHttpRequest(apiVersion string) *http.Request {
	request_url := fmt.Sprintf("/actions/network_configuration?tenantId=%s&runnerGroupId=%s&apiVersion=%s", s.tenantID, s.runnerGroupID, apiVersion)
	request := httptest.NewRequest(http.MethodGet, request_url, bodyBytes)
	request.Header.Set("Authorization", s.getAuthorizationHeader())
	return request
}

func (s *NetworkSettingsTestSuite) getAuthorizationHeader() string {
	return fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString(rawSignature))
}

func (s *NetworkSettingsTestSuite) TestGettingNetworkSettings() {
	responseBody, _ := json.Marshal(getSampleResponse(s.runnerGroupID))
	s.mockClient.Response.StatusCode = http.StatusOK
	s.mockClient.Response.Body = io.NopCloser(bytes.NewReader(responseBody))

	s.svc.HandleGetNetworkSettings(s.responseRecorder, s.request)

	s.Equal(http.StatusOK, s.responseRecorder.Code)
	expectedId := sampleResponseNetworkId
	expectedResponseData := LaunchNetworkConfigurationResponse{
		ID:        &expectedId,
		IsEnabled: true,
		VnetInjection: VnetInjection{
			Enabled: true,
			Subnets: []Subnet{
				{
					ResourceID: "/subscriptions/6d3acc75-039d-4a84-a0c2-883e492a72dd/resourceGroups/rgName/providers/Microsoft.Network/virtualNetworks/vnet-injection/subnets/default",
					Region:     "EastUs",
				},
			},
		},
	}
	resBody, _ := io.ReadAll(s.responseRecorder.Body)
	var actual LaunchNetworkConfigurationResponse
	_ = json.Unmarshal(resBody, &actual)
	s.Equal(expectedResponseData, actual)
}

func (s *NetworkSettingsTestSuite) TestUnassignedGroupReturnsDisabledVNet() {
	responseBody, _ := json.Marshal(getSampleResponseUnassignedGroup(s.runnerGroupID))
	s.mockClient.Response.StatusCode = http.StatusOK
	s.mockClient.Response.Body = io.NopCloser(bytes.NewReader(responseBody))

	s.svc.HandleGetNetworkSettings(s.responseRecorder, s.request)

	s.Equal(http.StatusOK, s.responseRecorder.Code)
	expectedId := unassignedResponseNetworkID
	expectedResponseData := LaunchNetworkConfigurationResponse{
		ID:        &expectedId,
		IsEnabled: true,
		VnetInjection: VnetInjection{
			Enabled: false,
			Subnets: []Subnet{},
		},
	}
	resBody, _ := io.ReadAll(s.responseRecorder.Body)
	var actual LaunchNetworkConfigurationResponse
	_ = json.Unmarshal(resBody, &actual)
	s.Equal(expectedResponseData, actual)
}

func (s *NetworkSettingsTestSuite) TestEmptyNetworkResourcesReturnsDisabledVNet() {
	sampleResponse := getSampleResponseEmptyNetworkResources(s.runnerGroupID)
	networkConfiguration := sampleResponse["networkConfiguration"].(map[string]interface{})
	networkConfiguration["networkResources"] = []map[string]interface{}{}
	responseBody, _ := json.Marshal(sampleResponse)
	s.mockClient.Response.StatusCode = http.StatusOK
	s.mockClient.Response.Body = io.NopCloser(bytes.NewReader(responseBody))

	s.svc.HandleGetNetworkSettings(s.responseRecorder, s.request)

	s.Equal(http.StatusOK, s.responseRecorder.Code)
	expectedId := unassignedResponseNetworkID
	expectedResponseData := LaunchNetworkConfigurationResponse{
		ID:        &expectedId,
		IsEnabled: true,
		VnetInjection: VnetInjection{
			Enabled: false,
			Subnets: []Subnet{},
		},
	}
	resBody, _ := io.ReadAll(s.responseRecorder.Body)
	var actual LaunchNetworkConfigurationResponse
	_ = json.Unmarshal(resBody, &actual)
	s.Equal(expectedResponseData, actual)
}

func (s *NetworkSettingsTestSuite) TestUnknownGroupReturnsDisabledVNet() {
	responseBody, _ := json.Marshal(getSampleResponseUnknownGroup(s.runnerGroupID))
	s.mockClient.Response.StatusCode = http.StatusOK
	s.mockClient.Response.Body = io.NopCloser(bytes.NewReader(responseBody))

	s.svc.HandleGetNetworkSettings(s.responseRecorder, s.request)

	s.Equal(http.StatusOK, s.responseRecorder.Code)
	expectedResponseData := LaunchNetworkConfigurationResponse{
		ID:        nil,
		IsEnabled: true,
		VnetInjection: VnetInjection{
			Enabled: false,
			Subnets: []Subnet{},
		},
	}
	resBody, _ := io.ReadAll(s.responseRecorder.Body)
	var actual LaunchNetworkConfigurationResponse
	_ = json.Unmarshal(resBody, &actual)
	s.Equal(expectedResponseData, actual)
}

func (s *NetworkSettingsTestSuite) TestDisabledNetworkConfiguration() {
	sampleResponse := getSampleResponse(s.runnerGroupID)
	networkConfiguration := sampleResponse["networkConfiguration"].(map[string]interface{})
	networkConfiguration["enabled"] = false

	responseBody, _ := json.Marshal(sampleResponse)
	s.mockClient.Response.StatusCode = http.StatusOK
	s.mockClient.Response.Body = io.NopCloser(bytes.NewReader(responseBody))

	s.svc.HandleGetNetworkSettings(s.responseRecorder, s.request)

	s.Equal(http.StatusOK, s.responseRecorder.Code)
	resBody, _ := io.ReadAll(s.responseRecorder.Body)
	var actual LaunchNetworkConfigurationResponse
	_ = json.Unmarshal(resBody, &actual)
	s.Equal(false, actual.IsEnabled)
}

func (s *NetworkSettingsTestSuite) TestUnexpectedNetworkResourceTypeReturnsDisabledVNet() {
	sampleResponse := getSampleResponse(s.runnerGroupID)
	networkConfigurations := sampleResponse["networkConfiguration"].(map[string]interface{})
	networkResources := networkConfigurations["networkResources"].([]map[string]interface{})
	networkResources[0]["type"] = "SomeOtherType"
	responseBody, _ := json.Marshal(sampleResponse)
	s.mockClient.Response.StatusCode = http.StatusOK
	s.mockClient.Response.Body = io.NopCloser(bytes.NewReader(responseBody))

	s.svc.HandleGetNetworkSettings(s.responseRecorder, s.request)

	s.Equal(http.StatusOK, s.responseRecorder.Code)
	expectedId := sampleResponseNetworkId
	expectedResponseData := LaunchNetworkConfigurationResponse{
		ID:        &expectedId,
		IsEnabled: true,
		VnetInjection: VnetInjection{
			Enabled: false,
			Subnets: []Subnet{},
		},
	}
	resBody, _ := io.ReadAll(s.responseRecorder.Body)
	var actual LaunchNetworkConfigurationResponse
	_ = json.Unmarshal(resBody, &actual)
	s.Equal(expectedResponseData, actual)
}

func (s *NetworkSettingsTestSuite) TestHandleErrorResponseFromNetworkService() {
	s.mockClient.Response.StatusCode = http.StatusForbidden

	s.svc.HandleGetNetworkSettings(s.responseRecorder, s.request)

	// assert
	s.Equal(http.StatusForbidden, s.responseRecorder.Code)
	expectedResponseData := LaunchNetworkConfigurationResponse{}
	resBody, _ := io.ReadAll(s.responseRecorder.Body)
	var actual LaunchNetworkConfigurationResponse
	_ = json.Unmarshal(resBody, &actual)
	s.Equal(expectedResponseData, actual)
}

const sampleResponseNetworkId = "51922ACD33F6D4CE89BD8E98E5977C110569BB8CC30214D47F9856E49406D1F0"

func getSampleResponse(runnerGroupID string) map[string]interface{} {
	return map[string]interface{}{
		"id":      runnerGroupID,
		"service": "actions",
		"networkConfiguration": map[string]interface{}{
			"id":      sampleResponseNetworkId,
			"name":    "configname",
			"enabled": true,
			"networkResources": []map[string]interface{}{
				{
					"resourceId":             "/subscriptions/6d3acc75-039d-4a84-a0c2-883e492a72dd/resourceGroups/rgName/providers/GitHub.Network/networkSettings/vnetinjection-eastus",
					"name":                   "vnetinjection-eastus",
					"apiVersion":             "2020-01-01",
					"location":               "EastUs",
					"state":                  "Registered",
					"businessId":             "3",
					"subnetId":               "/subscriptions/6d3acc75-039d-4a84-a0c2-883e492a72dd/resourceGroups/rgName/providers/Microsoft.Network/virtualNetworks/vnet-injection/subnets/default",
					"subnetSubscriptionId":   "6d3acc75-039d-4a84-a0c2-883e492a72dd",
					"tenantId":               "00000000-0000-0000-0000-000000000000",
					"type":                   "NetworkSettings",
					"networkConfigurationId": sampleResponseNetworkId,
					"subscription":           "6d3acc75-039d-4a84-a0c2-883e492a72dd",
					"resourceGroup":          "rgName",
					"id":                     "4af4c9a8e4f10386cca41c0ea19e048c0fae914d",
				},
			},
		},
	}
}

// The response expected when the runner group had a network configuration but has since been unassigned (i.e. no more vnet injection).
func getSampleResponseEmptyNetworkResources(runnerGroupID string) map[string]interface{} {
	return map[string]interface{}{
		"id":      runnerGroupID,
		"service": "actions",
		"networkConfiguration": map[string]interface{}{
			"id":               sampleResponseNetworkId,
			"networkResources": []map[string]interface{}{},
		},
	}
}

// The response expected when the runner group had a network configuration but has since been unassigned (i.e. no more vnet injection).
func getSampleResponseUnassignedGroup(runnerGroupID string) map[string]interface{} {
	return map[string]interface{}{
		"id":      runnerGroupID,
		"service": "actions",
		"networkConfiguration": map[string]interface{}{
			"id":               unassignedResponseNetworkID,
			"networkResources": []map[string]interface{}{},
		},
	}
}

// The response expected when the runner group has not been seen before by the network service.
func getSampleResponseUnknownGroup(runnerGroupID string) map[string]interface{} {
	return map[string]interface{}{
		"id":                   runnerGroupID,
		"service":              "actions",
		"networkConfiguration": nil,
	}
}
