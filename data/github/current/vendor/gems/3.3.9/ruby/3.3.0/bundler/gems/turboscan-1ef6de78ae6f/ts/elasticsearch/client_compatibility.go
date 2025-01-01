package elasticsearch

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/olivere/elastic"
	"github.com/pkg/errors"
)

func (e *Service) typelessUpdateMappingMeta(ctx context.Context, index string, meta map[string]interface{}) error {
	res, err := e.es.PerformRequest(ctx, elastic.PerformRequestOptions{
		Method: "PUT",
		Path:   fmt.Sprintf("/%s/_mapping", index),
		Body:   map[string]interface{}{"_meta": meta},
	})
	if err != nil {
		return err
	}
	if res.StatusCode >= 400 {
		return errors.New(fmt.Sprintf("Elasticsearch request to update mapping responded with status %d", res.StatusCode))
	}

	return nil
}

func (e *Service) typelessGetMappingMeta(ctx context.Context, index string) (map[string]interface{}, error) {
	res, err := e.es.PerformRequest(ctx, elastic.PerformRequestOptions{
		Method: "GET",
		Path:   fmt.Sprintf("/%s/_mapping", index),
	})
	if err != nil {
		return nil, err
	}
	if res.StatusCode >= 400 {
		return nil, errors.New(fmt.Sprintf("Elasticsearch request to get mapping responded with status %d", res.StatusCode))
	}

	var mappingResponse map[string]interface{}
	err = json.Unmarshal(res.Body, &mappingResponse)
	if err != nil {
		return nil, err
	}

	mapping, ok := mappingResponse[index].(map[string]interface{})["mappings"].(map[string]interface{})
	if !ok {
		return nil, errors.New("failed to get mapping meta")
	}

	meta, ok := mapping["_meta"].(map[string]interface{})
	if !ok {
		return map[string]interface{}{}, nil
	}
	return meta, nil
}
