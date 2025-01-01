/*
Package testhelper provides a set of tools used for testing things related with publishing and
consuming hydro message.
*/
package testhelper

import (
	"encoding/json"
	"fmt"
	"net/http"
	u "net/url"
	"testing"

	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	ghhydro "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"

	"github.com/github/notifyd/internal/pkg/hydro"
)

// BuildMemoryPublisher returns a hydro publisher that uses memory as it backend instead of kafka.
func BuildMemoryPublisher(t *testing.T) (*ghhydro.Publisher, chan ghhydro.Message) {
	t.Helper()

	stream := make(chan ghhydro.Message, 1)
	publisher, err := hydro.BuildMemoryPublisher(stream)
	require.NoError(t, err)

	return publisher, stream
}

// BuildHydroMsg returns a message that is encoded as if it had been received by a consumer.
func BuildHydroMsg(t *testing.T, msg proto.Message) ghhydro.Message {
	t.Helper()

	publisher, stream := BuildMemoryPublisher(t)
	err := publisher.Publish(msg.ProtoReflect().Interface())
	require.NoError(t, err)

	return <-stream
}

// BuildEnvelope retruns the given message wrapped on the hydro protobuf envelope.
func BuildEnvelope(t *testing.T, msg proto.Message) *hydro_pb.Envelope {
	t.Helper()

	hydroMsg := BuildHydroMsg(t, msg)
	var envelope hydro_pb.Envelope
	err := proto.Unmarshal(hydroMsg.Value, &envelope)
	require.NoError(t, err)

	return &envelope
}

// Reset sends a reset request to kafka-lite and aqueduct-lite to clean up any existing job or
// registered consumer.
//
// Both kafka-lite and aqueduct-lite expose reset endpoints that use a "magic word" for validation.
// ResetQueues works by first makinga request that is going to fail and return the word, and then
// uses that word to reset the queues.
//
// NOTE: It uses `assert` instead of `require` because it is meant to be used in integration tests.
// Integration tests in some cases spawn goroutines and `require` does not work when called from a
// goroutine different than the main one.
func Reset(t *testing.T, kafkaAdmin string) {
	t.Helper()

	mw := getMagicWord(t, kafkaAdmin)
	resetKafka(t, mw, kafkaAdmin)
}

func resetKafka(t *testing.T, magicWord, kafkaAdmin string) {
	resp := request(t, kafkaAdmin, u.Values{"magic_word": {magicWord}})
	defer resp.Body.Close()
	t.Logf("reset kafka-lite: %s", resp.Status)
}

func getMagicWord(t *testing.T, kafkaAdmin string) string {
	resp := request(t, kafkaAdmin, u.Values{})
	defer resp.Body.Close()

	var body map[string]string
	err := json.NewDecoder(resp.Body).Decode(&body)
	assert.NoError(t, err)

	return body["magic_word"]
}

func request(t *testing.T, url string, data u.Values) *http.Response {
	//nolint:noctx // We are OK with this for a test helper
	resp, err := http.PostForm(fmt.Sprintf("%s/admin/reset", url), data)
	assert.NoError(t, err)

	return resp
}
