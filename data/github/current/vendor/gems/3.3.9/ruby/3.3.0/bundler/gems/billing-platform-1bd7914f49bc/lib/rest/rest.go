package rest

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"time"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/models"
	"github.com/pkg/errors"
)

type CosmosTrigger struct {
	Body             string `json:"body"`
	Id               string `json:"id"`
	TriggerOperation string `json:"triggerOperation"`
	TriggerType      string `json:"triggerType"`
}

func GetTriggers(cfg *config.Config, databaseName string, collectionName string) ([]*CosmosTrigger, error) {
	cosmosKey := cfg.DatabaseKey

	method := "GET"
	resourceType := "triggers"
	resID := fmt.Sprintf("dbs/%s/colls/%s", databaseName, collectionName)
	requestDateString := strings.ToLower(time.Now().UTC().Format(http.TimeFormat))
	auth := buildCanonicalizedAuthHeader(method, resourceType, resID, requestDateString, "master", "1.0", cosmosKey)

	client := &http.Client{
		Transport: &http.Transport{
			DisableCompression: true,
			DisableKeepAlives:  true,
		},
	}

	url := fmt.Sprintf("%s%s/%s", cfg.DatabaseEndPoint, resID, resourceType)
	httpRequest, err := http.NewRequest(method, url, nil)
	if err != nil {
		return nil, errors.Wrap(err, "error getting triggers")
	}

	httpRequest.Header.Del("Accept-Encoding")
	httpRequest.Header["Accept"] = []string{"application/json"}
	httpRequest.Header["Authorization"] = []string{auth}
	httpRequest.Header["x-ms-date"] = []string{requestDateString}
	httpRequest.Header["x-ms-version"] = []string{"2018-12-31"}

	response, err := client.Do(httpRequest)
	if err != nil {
		return nil, errors.Wrap(err, "error getting triggers")
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		body, err := io.ReadAll(response.Body)
		if err != nil {
			return nil, fmt.Errorf("status code: %d, error reading body: %v", response.StatusCode, err)
		}
		return nil, fmt.Errorf("status code: %d, error: %v", response.StatusCode, string(body))
	}

	var triggers struct {
		Triggers []*CosmosTrigger `json:"Triggers"`
	}
	err = json.NewDecoder(response.Body).Decode(&triggers)
	if err != nil {
		return nil, errors.Wrap(err, "error decoding response body")
	}

	return triggers.Triggers, nil
}

func CreateOrUpdateTrigger(cfg *config.Config, databaseName string, collectionName string, triggerName, triggerOperation string, triggerType string, triggerExists bool, triggerText string) error {
	cosmosKey := cfg.DatabaseKey

	method := "POST"
	resourceType := "triggers"
	resId := fmt.Sprintf("dbs/%s/colls/%s", databaseName, collectionName)
	url := fmt.Sprintf("%s%s/%s", cfg.DatabaseEndPoint, resId, resourceType)
	if triggerExists {
		method = "PUT"
		resId = fmt.Sprintf("dbs/%s/colls/%s/triggers/%s", databaseName, collectionName, triggerName)
		url = fmt.Sprintf("%s%s", cfg.DatabaseEndPoint, resId)
	}

	requestDateString := strings.ToLower(time.Now().UTC().Format(http.TimeFormat))
	auth := buildCanonicalizedAuthHeader(method, resourceType, resId, requestDateString, "master", "1.0", cosmosKey)

	body := CosmosTrigger{
		triggerText,
		triggerName,
		triggerOperation,
		triggerType,
	}

	requestBody, err := json.Marshal(body)
	if err != nil {
		return errors.Wrap(err, "error creating trigger")
	}

	client := &http.Client{
		Transport: &http.Transport{
			DisableCompression: true,
			DisableKeepAlives:  true,
		},
	}

	httpRequest, err := http.NewRequest(method, url, bytes.NewBuffer(requestBody))
	if err != nil {
		return errors.Wrap(err, "error creating trigger")
	}

	httpRequest.Header.Del("Accept-Encoding")
	httpRequest.Header["Accept"] = []string{"application/json"}
	httpRequest.Header["Authorization"] = []string{auth}
	httpRequest.Header["x-ms-date"] = []string{requestDateString}
	httpRequest.Header["x-ms-version"] = []string{"2018-12-31"}
	httpRequest.Header["Content-Type"] = []string{"application/json"}

	httpRequest.Header["x-ms-offer-throughput"] = []string{"400"}

	response, err := client.Do(httpRequest)
	if err != nil {
		return errors.Wrap(err, "error creating trigger")
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK && response.StatusCode != http.StatusCreated {
		body, err := io.ReadAll(response.Body)
		if err != nil {
			return fmt.Errorf("status code: %d, error reading body: %v", response.StatusCode, err)
		}
		return fmt.Errorf("status code: %d, error: %v", response.StatusCode, string(body))
	}

	return nil
}

func CreateCollection(cfg *config.Config, overRideCollectionName string) error {
	databseName := cfg.DatabaseName
	cosmosKey := cfg.DatabaseKey
	collectionName := cfg.ContainerName
	if overRideCollectionName != "" {
		collectionName = overRideCollectionName
	}

	method := "POST"
	resourceType := "colls"
	resId := fmt.Sprintf("dbs/%s", databseName)
	requestDateString := strings.ToLower(time.Now().UTC().Format(http.TimeFormat))
	auth := buildCanonicalizedAuthHeader(method, resourceType, resId, requestDateString, "master", "1.0", cosmosKey)

	requestBody := fmt.Sprintf("{\"id\":\"%s\",\"partitionKey\":{\"paths\": [\"/partitionKey\"],\"kind\": \"Hash\",\"Version\": 2}}", collectionName)
	url := fmt.Sprintf("%s%s/%s", cfg.DatabaseEndPoint, resId, resourceType)

	client := &http.Client{
		Transport: &http.Transport{
			DisableCompression: true,
			DisableKeepAlives:  true,
		},
	}

	httpRequest, err := http.NewRequest(method, url, bytes.NewBuffer([]byte(requestBody)))
	if err != nil {
		return errors.Wrap(err, "error creating collection")
	}

	httpRequest.Header.Del("Accept-Encoding")
	httpRequest.Header["Accept"] = []string{"application/json"}
	httpRequest.Header["Authorization"] = []string{auth}
	httpRequest.Header["x-ms-date"] = []string{requestDateString}
	httpRequest.Header["x-ms-version"] = []string{"2018-12-31"}
	httpRequest.Header["Content-Type"] = []string{"application/json"}

	httpRequest.Header["x-ms-offer-throughput"] = []string{"400"}

	response, err := client.Do(httpRequest)
	if err != nil {
		return errors.Wrap(err, "error creating collection")
	}
	defer response.Body.Close()

	if err := handleError(http.StatusOK, response); err != nil {
		return errors.Wrap(err, "error creating collection")
	}

	return nil
}

func GetAllContainersForDatabase(cfg *config.Config, databaseName string) ([]string, error) {

	if cfg.IsProduction() {
		return nil, fmt.Errorf("ResetCollection is not allowed in production")
	}

	cosmosKey := cfg.DatabaseKey

	method := "GET"
	resourceType := "colls"
	resId := fmt.Sprintf("dbs/%s", databaseName)
	requestDateString := strings.ToLower(time.Now().UTC().Format(http.TimeFormat))
	auth := buildCanonicalizedAuthHeader(method, resourceType, resId, requestDateString, "master", "1.0", cosmosKey)

	url := fmt.Sprintf("%s%s/%s", cfg.DatabaseEndPoint, resId, resourceType)

	client := &http.Client{
		Transport: &http.Transport{
			DisableCompression: true,
			DisableKeepAlives:  true,
		},
	}
	continuation := ""
	results := make([]string, 0)
	for {
		httpRequest, err := http.NewRequest(method, url, nil)
		if err != nil {
			return nil, errors.Wrap(err, "error getting containers")
		}

		httpRequest.Header["Accept"] = []string{"application/json"}
		httpRequest.Header["Authorization"] = []string{auth}
		httpRequest.Header["x-ms-date"] = []string{requestDateString}
		httpRequest.Header["x-ms-version"] = []string{"2018-12-31"}
		httpRequest.Header["x-ms-max-item-count"] = []string{"100"}
		httpRequest.Header["Content-Type"] = []string{"application/query+json"}

		if continuation != "" {
			httpRequest.Header["x-ms-continuation"] = []string{continuation}
		}

		response, err := client.Do(httpRequest)
		if err != nil {
			return nil, errors.Wrap(err, "error getting containers")
		}
		defer response.Body.Close()

		if err := handleError(http.StatusOK, response); err != nil {
			return nil, err
		}

		var keys map[string]interface{}
		err = json.NewDecoder(response.Body).Decode(&keys)
		if err != nil {
			return nil, errors.Wrap(err, "error decoding response body")
		}

		foundKeys := (keys["DocumentCollections"].([]interface{}))
		for _, key := range foundKeys {
			results = append(results, key.(map[string]interface{})["id"].(string))
		}

		continuation = response.Header.Get("x-ms-continuation")
		if continuation == "" {
			break
		}
	}

	return results, nil
}

func GetAllDatabasesForServer(cfg *config.Config) ([]string, error) {

	if cfg.IsProduction() {
		return nil, fmt.Errorf("ResetCollection is not allowed in production")
	}

	cosmosKey := cfg.DatabaseKey

	method := "GET"
	resourceType := "dbs"
	resId := ""
	requestDateString := strings.ToLower(time.Now().UTC().Format(http.TimeFormat))
	auth := buildCanonicalizedAuthHeader(method, resourceType, resId, requestDateString, "master", "1.0", cosmosKey)

	url := fmt.Sprintf("%s%s/%s", cfg.DatabaseEndPoint, resId, resourceType)

	client := &http.Client{
		Transport: &http.Transport{
			DisableCompression: true,
			DisableKeepAlives:  true,
		},
	}
	continuation := ""
	results := make([]string, 0)
	for {
		httpRequest, err := http.NewRequest(method, url, nil)
		if err != nil {
			return nil, errors.Wrap(err, "error getting databases")
		}

		httpRequest.Header["Accept"] = []string{"application/json"}
		httpRequest.Header["Authorization"] = []string{auth}
		httpRequest.Header["x-ms-date"] = []string{requestDateString}
		httpRequest.Header["x-ms-version"] = []string{"2018-12-31"}
		httpRequest.Header["x-ms-max-item-count"] = []string{"100"}
		httpRequest.Header["Content-Type"] = []string{"application/query+json"}

		if continuation != "" {
			httpRequest.Header["x-ms-continuation"] = []string{continuation}
		}

		response, err := client.Do(httpRequest)
		if err != nil {
			return nil, errors.Wrap(err, "error getting databases")
		}
		defer response.Body.Close()

		if err := handleError(http.StatusOK, response); err != nil {
			return nil, err
		}

		var keys map[string]interface{}
		err = json.NewDecoder(response.Body).Decode(&keys)
		if err != nil {
			return nil, errors.Wrap(err, "error decoding response body")
		}

		foundKeys := (keys["Databases"].([]interface{}))
		for _, key := range foundKeys {
			results = append(results, key.(map[string]interface{})["id"].(string))
		}

		continuation = response.Header.Get("x-ms-continuation")
		if continuation == "" {
			break
		}
	}

	return results, nil
}

func GetAllDocumentKeys(cfg *config.Config) ([]*models.Key, error) {

	if cfg.IsProduction() {
		return nil, fmt.Errorf("ResetCollection is not allowed in production")
	}

	databseName := cfg.DatabaseName
	containerName := cfg.ContainerName
	cosmosKey := cfg.DatabaseKey

	method := "POST"
	resourceType := "docs"
	resId := fmt.Sprintf("dbs/%s/colls/%s", databseName, containerName)
	requestDateString := strings.ToLower(time.Now().UTC().Format(http.TimeFormat))
	auth := buildCanonicalizedAuthHeader(method, resourceType, resId, requestDateString, "master", "1.0", cosmosKey)

	var jsonData = []byte(`{
		"query": "SELECT * FROM c",
		"parameters": []
	}`)

	url := fmt.Sprintf("%s%s/%s", cfg.DatabaseEndPoint, resId, resourceType)

	client := &http.Client{
		Transport: &http.Transport{
			DisableCompression: true,
			DisableKeepAlives:  true,
		},
	}
	continuation := ""
	results := make([]*models.Key, 0)
	for {
		httpRequest, err := http.NewRequest(method, url, bytes.NewBuffer(jsonData))
		if err != nil {
			return nil, errors.Wrap(err, "error getting keys")
		}

		httpRequest.Header["Accept"] = []string{"application/json"}
		httpRequest.Header["Authorization"] = []string{auth}
		httpRequest.Header["x-ms-date"] = []string{requestDateString}
		httpRequest.Header["x-ms-version"] = []string{"2018-12-31"}
		httpRequest.Header["x-ms-max-item-count"] = []string{"10"}
		httpRequest.Header["x-ms-documentdb-query-enablecrosspartition"] = []string{"True"}
		httpRequest.Header["x-ms-documentdb-isquery"] = []string{"True"}
		httpRequest.Header["Content-Type"] = []string{"application/query+json"}

		if continuation != "" {
			httpRequest.Header["x-ms-continuation"] = []string{continuation}
		}

		response, err := client.Do(httpRequest)
		if err != nil {
			return nil, errors.Wrap(err, "error getting keys")
		}
		defer response.Body.Close()

		if err := handleError(http.StatusOK, response); err != nil {
			return nil, err
		}

		var keys map[string]interface{}
		err = json.NewDecoder(response.Body).Decode(&keys)
		if err != nil {
			return nil, errors.Wrap(err, "error decoding response body")
		}

		foundKeys := (keys["Documents"].([]interface{}))
		for _, key := range foundKeys {
			x := key.(map[string]interface{})
			id := x["id"].(string)
			partitionKey := x["partitionKey"].(string)
			results = append(results, &models.Key{Id: id, PartitionKey: partitionKey})
		}

		continuation = response.Header.Get("x-ms-continuation")
		if continuation == "" {
			break
		}
	}

	return results, nil
}

func Query(cfg *config.Config, query string) ([]map[string]interface{}, error) {

	if cfg.IsProduction() {
		return nil, fmt.Errorf("Query is not allowed in production")
	}

	databseName := cfg.DatabaseName
	containerName := cfg.ContainerName
	cosmosKey := cfg.DatabaseKey

	method := "POST"
	resourceType := "docs"
	resId := fmt.Sprintf("dbs/%s/colls/%s", databseName, containerName)
	requestDateString := strings.ToLower(time.Now().UTC().Format(http.TimeFormat))
	auth := buildCanonicalizedAuthHeader(method, resourceType, resId, requestDateString, "master", "1.0", cosmosKey)

	var jsonData = []byte(`{
		"query": "` + query + `",
		"parameters": []
	}`)

	url := fmt.Sprintf("%s%s/%s", cfg.DatabaseEndPoint, resId, resourceType)

	client := &http.Client{
		Transport: &http.Transport{
			DisableCompression: true,
			DisableKeepAlives:  true,
		},
	}

	continuation := ""
	results := make([]map[string]interface{}, 0)
	for {
		httpRequest, err := http.NewRequest(method, url, bytes.NewBuffer(jsonData))
		if err != nil {
			return nil, errors.Wrap(err, "error querying")
		}

		httpRequest.Header["Accept"] = []string{"application/json"}
		httpRequest.Header["Authorization"] = []string{auth}
		httpRequest.Header["x-ms-date"] = []string{requestDateString}
		httpRequest.Header["x-ms-version"] = []string{"2018-12-31"}
		httpRequest.Header["x-ms-max-item-count"] = []string{"1000"}
		httpRequest.Header["x-ms-documentdb-query-enablecrosspartition"] = []string{"True"}
		httpRequest.Header["x-ms-documentdb-isquery"] = []string{"True"}
		httpRequest.Header["Content-Type"] = []string{"application/query+json"}

		if continuation != "" {
			httpRequest.Header["x-ms-continuation"] = []string{continuation}
		}

		response, err := client.Do(httpRequest)
		if err != nil {
			return nil, errors.Wrap(err, "error querying")
		}
		defer response.Body.Close()

		if err := handleError(http.StatusOK, response); err != nil {
			return nil, err
		}

		var itemResults map[string]interface{}
		err = json.NewDecoder(response.Body).Decode(&itemResults)
		if err != nil {
			return nil, errors.Wrap(err, "error decoding response body")
		}

		foundKeys := (itemResults["Documents"].([]interface{}))
		for _, key := range foundKeys {
			x := key.(map[string]interface{})

			results = append(results, x)
		}

		continuation = response.Header.Get("x-ms-continuation")
		if continuation == "" {
			break
		}
	}

	return results, nil
}

func CreateDocument(cfg *config.Config, item string, pk string) (map[string]interface{}, error) {
	databseName := cfg.DatabaseName
	containerName := cfg.ContainerName
	endpoint := cfg.DatabaseEndPoint
	cosmosKey := cfg.DatabaseKey

	method := "POST"
	resourceType := "docs"
	resId := fmt.Sprintf("dbs/%s/colls/%s", databseName, containerName)
	requestDateString := strings.ToLower(time.Now().UTC().Format(http.TimeFormat))
	auth := buildCanonicalizedAuthHeader(method, resourceType, resId, requestDateString, "master", "1.0", cosmosKey)
	url := fmt.Sprintf("%s%s/%s", endpoint, resId, resourceType)

	client := &http.Client{
		Transport: &http.Transport{
			DisableCompression: true,
			DisableKeepAlives:  true,
		},
	}

	httpRequest, err := http.NewRequest(method, url, bytes.NewBuffer([]byte(item)))
	if err != nil {
		return nil, errors.Wrap(err, "error creating document")
	}

	httpRequest.Header["Accept"] = []string{"application/json"}
	httpRequest.Header["Authorization"] = []string{auth}
	httpRequest.Header["x-ms-date"] = []string{requestDateString}
	httpRequest.Header["x-ms-version"] = []string{"2020-11-05"}
	httpRequest.Header["Content-Type"] = []string{"application/json"}
	httpRequest.Header["x-ms-documentdb-partitionkey"] = []string{"[\"" + pk + "\"]"}

	response, err := client.Do(httpRequest)
	if err != nil {
		return nil, errors.Wrap(err, "error creating document")
	}
	defer response.Body.Close()

	if err := handleError(http.StatusCreated, response); err != nil {
		return nil, err
	}

	var itemResults map[string]interface{}
	err = json.NewDecoder(response.Body).Decode(&itemResults)
	if err != nil {
		return nil, errors.Wrap(err, "error decoding response body")
	}

	return itemResults, nil
}

// https://github.com/Azure/azure-sdk-for-go/blob/92067bebbdd5594e2497af893f60d077f87b37dd/sdk/data/azcosmos/shared_key_credential.go#L50
func computeHMACSHA256(accountKey string, s string) (base64String string) {
	hexKey, err := base64.StdEncoding.DecodeString(accountKey)
	if err != nil {
		return ""
	}

	h := hmac.New(sha256.New, hexKey)
	_, _ = h.Write([]byte(s))

	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

// lue = c.buildCanonicalizedAuthHeader(req.Raw().Method, resourceTypePath, resourceAddress, req.Raw().Header.Get(headerXmsDate), "master", "1.0")
// where date is like time.RFC1123 but hard-codes GMT as the time zone
func buildCanonicalizedAuthHeader(method, resourceType, resourceAddress, xmsDate, tokenType, version, accountKey string) string {
	if method == "" || resourceType == "" {
		return ""
	}

	resourceAddress, _ = url.PathUnescape(resourceAddress)

	// https://docs.microsoft.com/en-us/rest/api/cosmos-db/access-control-on-cosmosdb-resources#constructkeytoken
	stringToSign := join(strings.ToLower(method), "\n", strings.ToLower(resourceType), "\n", resourceAddress, "\n", strings.ToLower(xmsDate), "\n", "", "\n")
	signature := computeHMACSHA256(accountKey, stringToSign)

	return url.QueryEscape(join("type=" + tokenType + "&ver=" + version + "&sig=" + signature))
}

func join(strs ...string) string {
	var sb strings.Builder
	for _, str := range strs {
		sb.WriteString(str)
	}
	return sb.String()
}

func handleError(expectedStatus int, response *http.Response) error {
	if response.StatusCode != expectedStatus {
		responseDump, err := httputil.DumpResponse(response, true)
		if err != nil {
			return errors.Wrap(err, "error dumping response")
		}

		fmt.Printf("response:\n%s\r\n", string(responseDump))
		return fmt.Errorf("status code: %d", response.StatusCode)
	}
	return nil
}
