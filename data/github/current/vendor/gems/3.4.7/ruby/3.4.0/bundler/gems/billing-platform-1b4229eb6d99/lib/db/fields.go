package db

import (
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/kvp"
)

func GetItemResponseLoggerFields(itemResponse azcosmos.ItemResponse, timeElapsed time.Duration, err error) []kvp.Field {
	fields := []kvp.Field{
		kvp.Float32("db.cosmosdb.request_charge", itemResponse.RequestCharge),
	}

	if timeElapsed != 0 {
		fields = append(fields, kvp.Int64("db.cosmosdb.time_elapsed", timeElapsed.Milliseconds()))
	}

	if err != nil {
		fields = append(fields, kvp.Int("db.status_code", GetErrorStatusCode(err)))
	} else {
		if itemResponse.RawResponse == nil {
			fields = append(fields, kvp.Int("db.status_code", 0))
		} else {
			fields = append(fields, kvp.Int("db.status_code", itemResponse.RawResponse.StatusCode))
		}
	}

	return fields
}

func GetErrorStatusCode(err error) int {
	azError := AsAzError(err)

	if azError != nil {
		return azError.StatusCode
	}

	return 0
}
