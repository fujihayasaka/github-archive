// Package cocofix defines cocofix types, parser and mapping with alerts
package cocofix

import (
	"encoding/json"
)

func parseResponseJson(input []byte) (CocofixResponse, error) {
	var response CocofixResponse
	err := json.Unmarshal(input, &response)
	if err != nil {
		return nil, err
	}
	return response, nil
}
