package hydro

import (
	"bytes"
	"encoding/json"
	"strings"

	"github.com/golang/protobuf/jsonpb" // nolint: staticcheck
	"github.com/golang/protobuf/proto"  // nolint: staticcheck
)

type encodedEvent struct {
	Schema       string `json:"schema"`
	Value        string `json:"value"`
	PartitionKey string `json:"partition_key,omitempty"`
}

type encodedRequest struct {
	Events []*encodedEvent `json:"events"`
}

func encodeProtoMessagesAsJSON(messages []proto.Message, partitionKey string) (string, error) {
	req := &encodedRequest{}
	marshaler := &jsonpb.Marshaler{}
	for _, proto := range messages {
		msg, err := marshaler.MarshalToString(proto)
		if err != nil {
			return "", err
		}
		req.Events = append(req.Events, &encodedEvent{
			Schema:       getSchemaNameForMessage(proto),
			Value:        msg,
			PartitionKey: partitionKey,
		})
	}
	var body bytes.Buffer
	err := json.NewEncoder(&body).Encode(req)
	return body.String(), err
}

func getSchemaNameForMessage(message proto.Message) string {
	return strings.Replace(proto.MessageName(message), "hydro.schemas.", "", 1) // nolint: staticcheck
}
