package stash

import "github.com/github/github-telemetry-go/kvp"

func KvpFieldsToMap(fields []kvp.Field) map[string]string {
	output := map[string]string{}

	for _, attr := range kvp.MapAttributes(nil, fields...) {
		output[string(attr.Key)] = attr.Value.Emit()
	}
	return output
}

func MapToKvpFields(m map[string]string) []kvp.Field {
	output := []kvp.Field{}

	for k, v := range m {
		output = append(output, kvp.String(k, v))
	}

	return output
}
