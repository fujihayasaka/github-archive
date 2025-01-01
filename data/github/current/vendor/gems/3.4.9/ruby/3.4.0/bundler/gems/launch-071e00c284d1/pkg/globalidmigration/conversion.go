package globalidmigration

import (
	"context"
	"encoding/json"
	"strconv"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
)

func ConvertPayloadIDs(ctx context.Context, obs *observability.Observability, ghtwirp ghtwirp.Client, operation string, payload []byte) ([]byte, error) {
	if !launchconfig.UsingNextGIDs() {
		return payload, nil
	}

	var jsonData map[string]any

	err := json.Unmarshal(payload, &jsonData)
	if err != nil {
		return payload, err
	}

	err = convertJSONGlobalIDs(ctx, obs, ghtwirp, operation, "", jsonData)
	if err != nil {
		return payload, err
	}

	newPayload, err := json.Marshal(jsonData)
	if err != nil {
		return payload, err
	}

	return newPayload, nil
}

func convertJSONGlobalIDs(ctx context.Context, obs *observability.Observability, ghtwirp ghtwirp.Client, operation, field string, jsonData map[string]interface{}) error {
	var err error
	for key, value := range jsonData {
		var fieldName = field + "." + key

		switch v := value.(type) {
		case map[string]interface{}:
			err = convertJSONGlobalIDs(ctx, obs, ghtwirp, operation, fieldName, v)
			if err != nil {
				return err
			}
		case string:
			// Attempt to convert the value to the Next Global ID format
			nextGID, convertErr := convertLegacyID(ctx, obs, ghtwirp, operation, fieldName, v)
			if convertErr != nil {
				obs.ErrorWithFields(ctx, "could not convert legacy global id in json payload", convertErr,
					kvp.String("operation", operation),
					kvp.String("field", fieldName),
					kvp.String("legacy_global_id", v))
				continue
			}

			// Update the map if the value has changed
			if nextGID != v {
				jsonData[key] = nextGID
			}
		}
	}
	return err
}

func convertLegacyID(ctx context.Context, obs *observability.Observability, ghtwirp ghtwirp.Client, operation, field, legacyOrNextGID string) (string, error) {
	if !types.IsConvertibleGlobalID(legacyOrNextGID) {
		// This is expected in many cases, so return the original value and don't return an error
		obs.Statter.Counter(ctx, "global_ids.replace_webhook_data_legacy_gid",
			statter.Tags{"operation": operation, "result": "no_change", "convertible_id": strconv.FormatBool(false)}, 1)
		return legacyOrNextGID, nil
	}

	nextGID, err := ghtwirp.GetNextGlobalID(ctx, legacyOrNextGID)
	if err != nil {
		obs.Statter.Counter(ctx, "global_ids.replace_webhook_data_legacy_gid",
			statter.Tags{"operation": operation, "result": "failed", "convertible_id": strconv.FormatBool(true)}, 1)
		obs.Report(ctx, errors.Wrap(err, "could not get next global id during webhook data extraction, falling back to legacy id"),
			kvp.String("operation", operation),
			kvp.String("field", field),
			kvp.String("legacy_global_id", legacyOrNextGID))
		return legacyOrNextGID, err
	}

	if legacyOrNextGID != nextGID.String() {
		obs.Statter.Counter(ctx, "global_ids.replace_webhook_data_legacy_gid",
			statter.Tags{"operation": operation, "result": "converted", "convertible_id": strconv.FormatBool(true)}, 1)
		obs.Debug(ctx, "Converting legacy gid to next gid in webhook data",
			kvp.String("gh.launch.operation.name", operation),
			kvp.String("gh.launch.field", field),
			kvp.String("gh.launch.legacy_global_id", legacyOrNextGID),
			kvp.String("gh.launch.next_global_id", nextGID.String()))
	} else {
		// If we arrive here, it suggests that types.IsConvertibleGlobalID() is missing a check
		obs.Statter.Counter(ctx, "global_ids.replace_webhook_data_legacy_gid",
			statter.Tags{"operation": operation, "result": "no_change", "convertible_id": strconv.FormatBool(true)}, 1)
		obs.Error(ctx, "Called GetNextGlobalID() after checking IsConvertibleGlobalID() but received the same id back",
			kvp.String("gh.launch.operation.name", operation),
			kvp.String("gh.launch.field", field),
			kvp.String("gh.launch.legacy_global_id", legacyOrNextGID))
	}

	return nextGID.String(), nil
}
