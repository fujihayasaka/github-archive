package admin

import (
	"bytes"
	"context"
	"encoding/json"
	"strconv"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/pkg/errors"
)

type QueryResults struct {
	PartitionKey             string
	Results                  string
	QueryString              string
	QueryTime                time.Duration
	ResultsCount             int
	RequestCharge            float32
	RetrievedDocumentSizeKiB float64
	OutputDocumentSizeKiB    float64
}

func unmarshallQueryResponse(queryResponse azcosmos.QueryItemsResponse, items *[]string) error {
	for _, item := range queryResponse.Items {
		var out bytes.Buffer
		err := json.Indent(&out, item, "", "  ")

		if err != nil {
			return errors.Errorf("Failed to unmarshall query response: %v", err)
		}

		*items = append(*items, out.String())
	}

	return nil
}

func (s *AdminServer) getQueryItems(ctx context.Context, queryString string, partitionKey string) (string, time.Duration, int, float32, float64, float64, error) {
	var requestCharge float32
	var elapsed time.Duration
	var totalResultsCount int
	var totalRetrievedDocumentSize float64
	var totalOutputDocumentSize float64

	options := &azcosmos.QueryOptions{
		PageSizeHint: -1,
	}

	queryPager := s.ReadOnlyDBCon.NewQueryItemsPager(queryString, azcosmos.NewPartitionKeyString(partitionKey), options)
	items := make([]string, 0)
	for queryPager.More() {
		start := time.Now()
		queryResponse, err := queryPager.NextPage(ctx)
		if err != nil {
			s.Logger.Error("QueryItems failed", kvp.String("db.cosmosdb.query", queryString), kvp.String("db.cosmosdb.partition_key", s.PK))
			return "", time.Since(start), totalResultsCount, requestCharge, convertToKiB(totalRetrievedDocumentSize), convertToKiB(totalOutputDocumentSize), errors.Wrap(err, "QueryItems failed")
		}

		requestCharge += queryResponse.RequestCharge

		// see https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/query-metrics for more info
		// about these query metrics
		queryMetrics := *queryResponse.QueryMetrics
		for _, metric := range strings.Split(queryMetrics, ";") {
			if strings.Contains(metric, "retrievedDocumentSize") {
				retrievedDocumentSize, convertErr := strconv.Atoi(strings.Split(metric, "=")[1])
				if convertErr == nil {
					totalRetrievedDocumentSize += float64(retrievedDocumentSize)
				}
			}

			if strings.Contains(metric, "outputDocumentSize") {
				outputDocumentSize, convertErr := strconv.Atoi(strings.Split(metric, "=")[1])
				if convertErr == nil {
					totalOutputDocumentSize += float64(outputDocumentSize)
				}
			}
		}

		if err := unmarshallQueryResponse(queryResponse, &items); err != nil {
			s.Logger.Error("QueryItems Unmarshal failed", kvp.String("db.cosmosdb.query", queryString), kvp.String("db.cosmosdb.partition_key", s.PK))
			return "", time.Since(start), totalResultsCount, requestCharge, convertToKiB(totalRetrievedDocumentSize), convertToKiB(totalOutputDocumentSize), err
		}

		elapsed += time.Since(start)
		totalResultsCount += len(queryResponse.Items)
		s.Logger.Debug("QueryItems Success",
			kvp.String("db.cosmosdb.query", queryString),
			kvp.String("db.cosmosdb.partition_key", s.PK),
			kvp.Int64("db.cosmosdb.time_elapsed", elapsed.Milliseconds()),
			kvp.Float32("db.cosmosdb.request_charge", requestCharge),
		)

	}

	result := strings.Join(items, ",")

	return result, elapsed, totalResultsCount, requestCharge, convertToKiB(totalRetrievedDocumentSize), convertToKiB(totalOutputDocumentSize), nil
}

func convertToKiB(bytes float64) float64 {
	return float64(bytes) / 1024
}
