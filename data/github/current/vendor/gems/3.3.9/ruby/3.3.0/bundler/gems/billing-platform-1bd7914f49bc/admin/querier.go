package admin

import (
	"bytes"
	"context"
	"encoding/json"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/pkg/errors"
)

type QueryResults struct {
	PartitionKey  string
	Results       string
	QueryString   string
	QueryTime     time.Duration
	ResultsCount  int
	RequestCharge float32
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

func (s *AdminServer) getQueryItems(ctx context.Context, queryString string, partitionKey string) (string, time.Duration, int, float32, error) {
	var requestCharge float32
	var elapsed time.Duration
	var totalResultsCount int

	options := &azcosmos.QueryOptions{
		PageSizeHint: -1,
	}

	queryPager := s.ReadOnlyDBCon.NewQueryItemsPager(queryString, azcosmos.NewPartitionKeyString(partitionKey), options)
	items := make([]string, 0)
	for queryPager.More() {
		start := time.Now()
		queryResponse, err := queryPager.NextPage(ctx)
		requestCharge += queryResponse.RequestCharge

		if err != nil {
			s.Logger.Error("QueryItems failed", kvp.String("db.cosmosdb.query", queryString), kvp.String("db.cosmosdb.partition_key", s.PK))
			return "", time.Since(start), totalResultsCount, requestCharge, errors.Wrap(err, "QueryItems failed")
		}

		if err := unmarshallQueryResponse(queryResponse, &items); err != nil {
			s.Logger.Error("QueryItems Unmarshal failed", kvp.String("db.cosmosdb.query", queryString), kvp.String("db.cosmosdb.partition_key", s.PK))
			return "", time.Since(start), totalResultsCount, requestCharge, err
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

	return result, elapsed, totalResultsCount, requestCharge, nil
}
