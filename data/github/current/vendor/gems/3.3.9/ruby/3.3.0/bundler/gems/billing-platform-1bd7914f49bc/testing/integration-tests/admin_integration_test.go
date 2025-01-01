//go:build integration
// +build integration

package integrationtests_test

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/okta"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/mocks"
)

func Test_AdminIntegration_adminQueryHandlerWithCorrectOktaUser(t *testing.T) {
	client, _ := integration.NewTestAdminClient(t, integration.ClientOptions{})

	response := httptest.NewRecorder()
	request, _ := http.NewRequest(http.MethodPost, "/query", nil)

	form := url.Values{}
	form.Add("query", "select * from c")
	form.Add("partitionKey", "customer:1")
	request.PostForm = form
	request.Header.Add("Content-Type", "application/x-www-form-urlencoded")

	// Set the Okta HMAC headers
	request = request.Clone(context.WithValue(request.Context(), okta.CtxKey{}, "monalisa"))

	client.AdminServer.QueryHandler(response, request)

	res := response.Result()
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		t.Errorf("Expected status OK; got %v", res.StatusCode)
	}

	data, _ := io.ReadAll(res.Body)

	if !strings.Contains(string(data), "Results") {
		t.Errorf("Expected body to contain 'Results'; got %v", string(data))
	}
}

func Test_AdminIntegration_adminQueryHandlerWithMissingOktaUser(t *testing.T) {
	client, _ := integration.NewTestAdminClient(t, integration.ClientOptions{})

	response := httptest.NewRecorder()
	request, _ := http.NewRequest(http.MethodPost, "/query", nil)

	form := url.Values{}
	form.Add("query", "select * from c")
	form.Add("partitionKey", "customer:1")
	request.PostForm = form
	request.Header.Add("Content-Type", "application/x-www-form-urlencoded")

	client.AdminServer.QueryHandler(response, request)

	res := response.Result()
	defer res.Body.Close()

	if res.StatusCode != http.StatusInternalServerError {
		t.Errorf("Expected status 500; got %v", res.StatusCode)
	}

	data, _ := io.ReadAll(res.Body)

	if string(data) == "failed to get username" {
		t.Errorf("Expected body to contain 'failed to get username'; got %v", string(data))
	}
}

func Test_AdminIntegration_adminQueryHandlerRedirectsToQueryForm(t *testing.T) {
	client, _ := integration.NewTestAdminClient(t, integration.ClientOptions{})

	response := httptest.NewRecorder()
	request, _ := http.NewRequest(http.MethodGet, "/query", nil)

	client.AdminServer.QueryHandler(response, request)

	res := response.Result()
	defer res.Body.Close()

	if res.StatusCode != http.StatusTemporaryRedirect {
		t.Errorf("Expected status StatusTemporaryRedirect; got %v", res.StatusCode)
	}

	locationHeader := res.Header.Get("Location")
	if locationHeader != "/" {
		t.Errorf("Expected redirect to /, got %v", locationHeader)
	}
}

func Test_AdminIntegration_readOnlyDatabasePreventsWriteOperation(t *testing.T) {
	client, _ := integration.NewTestAdminClient(t, integration.ClientOptions{})

	ctx := context.Background()
	logger := &mocks.Logger{}

	customer := models.NewCustomerFrom("1234", "", false, models.NoBillingTarget, "", "", "", "enterprise", false, 0, []string{"actions", "git_lfs", "copilot", "ghec", "ghas"}, true, false, false, false, &models.TradeScreening{}, models.CostCenterActive)
	_, err := client.ReadOnlyDB.CreateIfNotExists(ctx, logger, customer)

	if err == nil {
		t.Error("We expected an error preventing us from creating a customer in a read-only database")
	}
}

func Test_AdminIntegration_adminPingRRequest(t *testing.T) {
	client, _ := integration.NewTestAdminClient(t, integration.ClientOptions{})

	response := httptest.NewRecorder()
	request, _ := http.NewRequest(http.MethodGet, "/_ping", nil)

	client.AdminServer.PingHandler(response, request)

	res := response.Result()
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		t.Errorf("Expected status OK; got %v", res.StatusCode)
	}

	data, _ := io.ReadAll(res.Body)

	if string(data) != "pong" {
		t.Errorf("Expected body to contain 'pong'; got %v", string(data))
	}
}

func Test_AdminIntegration_adminRoutingToRoot(t *testing.T) {
	client, _ := integration.NewTestAdminClient(t, integration.ClientOptions{})

	request, _ := http.NewRequest(http.MethodGet, "/", nil)
	response := httptest.NewRecorder()

	client.AdminServer.RootHandler(response, request)

	res := response.Result()
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		t.Errorf("Expected status OK; got %v", res.StatusCode)
	}

	data, _ := io.ReadAll(res.Body)

	if !strings.Contains(string(data), "Cosmos Query") {
		t.Errorf("Expected body to contain 'Query tool'; got %v", string(data))
	}

	if strings.Contains(string(data), "Results") {
		t.Errorf("Expected body to not contain 'Results'; got %v", string(data))
	}
}

func Test_AdminIntegration_adminStaticFileRendering(t *testing.T) {
	client, _ := integration.NewTestAdminClient(t, integration.ClientOptions{})

	request, _ := http.NewRequest(http.MethodGet, "/static/example.txt", nil)
	response := httptest.NewRecorder()

	client.AdminServer.StaticFileHandler(response, request)

	res := response.Result()
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		t.Errorf("Expected status OK; got %v", res.StatusCode)
	}

	data, _ := io.ReadAll(res.Body)

	if string(data) != "This is a static file that we can view at /static/example.txt" {
		t.Errorf("Expected body to contain 'This is a static file that we can view at /static/example.txt'; got %v", string(data))
	}
}
