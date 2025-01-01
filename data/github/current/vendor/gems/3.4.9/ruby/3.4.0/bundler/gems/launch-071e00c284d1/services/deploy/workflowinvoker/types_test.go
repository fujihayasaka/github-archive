package workflowinvoker

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/go-github/v25/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/flow/flowevents"
)

func Test_Invocation_WireCompat_Actor_To_ExecutingActor(t *testing.T) {

	oldFormat, err := os.ReadFile(filepath.Join("fixtures", "invocation_push.json"))
	require.NoError(t, err)

	newFormat, err := os.ReadFile(filepath.Join("fixtures", "invocation_push_actor_to_executing_actor.json"))
	require.NoError(t, err)

	var (
		old *Invocation
		new *Invocation
	)

	err = json.Unmarshal(oldFormat, &old)
	require.NoError(t, err)

	err = json.Unmarshal(newFormat, &new)
	require.NoError(t, err)

	require.Equal(t, old, new)
}

func Test_Invocation_WireCompat_ExecutingActor_To_Actor(t *testing.T) {

	in := Invocation{ExecutingActor: InvokingActor{ID: "global_id", Login: "monalisa"}}

	out, err := json.Marshal(in)
	require.NoError(t, err)

	got := make(map[string]any)

	err = json.Unmarshal(out, &got)
	require.NoError(t, err)

	require.Contains(t, got, "Actor")
	require.Contains(t, got, "ExecutingActor")
	require.Contains(t, got, "TriggeringActor")
}

// Test_Unmarshal_Invocation tests whether a previously serialized invocation can still be
// successfully deserialized. Invocations are used in S2S calls via a queue, so we must not
// make breaking changes to the struct.
func Test_Unmarshal_Invocation(t *testing.T) {
	readFixture := func(fixture string) ([]byte, error) {
		return os.ReadFile(filepath.Join("fixtures", fixture+".json"))
	}

	jsonBody, err := readFixture("invocation_push")
	require.NoError(t, err)

	var invocation Invocation
	err = json.Unmarshal(jsonBody, &invocation)
	require.NoError(t, err)

	_, isPushEvent := invocation.Event.Ghe.(*github.PushEvent)
	assert.True(t, isPushEvent)
}

func Test_Unmarshal_Invocation_ExistingCheckSuite(t *testing.T) {
	readFixture := func(fixture string) ([]byte, error) {
		return os.ReadFile(filepath.Join("fixtures", fixture+".json"))
	}

	// This fixture contains fields on the ExistingCheckSuite
	// that are not present in the current CheckSuiteState struct.
	jsonBody, err := readFixture("invocation_existing_check_suite")
	require.NoError(t, err)

	var invocation Invocation
	err = json.Unmarshal(jsonBody, &invocation)
	require.NoError(t, err)

	require.NotNil(t, invocation.ExistingCheckSuite)
	require.Equal(t, "Blank", invocation.ExistingCheckSuite.FlowIdentifier)
}

func Test_RoundtripMarshalInvocation_WithPushEvent(t *testing.T) {
	readFixture := func(fixture string) ([]byte, error) {
		return os.ReadFile(filepath.Join("fixtures", fixture+".json"))
	}

	payload, err := readFixture("push")
	require.NoError(t, err)

	invocationWithPayload := pushInvocation
	invocationWithPayload.Event.OriginTime = time.Time{}
	invocationWithPayload.Event.Payload = payload

	ghe, err := flowevents.ParseEventWebHook("push", payload)
	require.NoError(t, err)
	invocationWithPayload.Event.Ghe = ghe

	jsonBody, err := json.Marshal(invocationWithPayload)
	require.NoError(t, err)

	var invocation Invocation
	err = json.Unmarshal(jsonBody, &invocation)
	require.NoError(t, err)

	assert.Equal(t, invocationWithPayload, invocation)

	_, isPushEvent := invocation.Event.Ghe.(*github.PushEvent)
	assert.True(t, isPushEvent)
}

func Test_RoundtripMarshalInvocation_WithScheduleEvent(t *testing.T) {
	scheduleInvocation := pushInvocation
	scheduleInvocation.Event.OriginTime = time.Time{}
	scheduleInvocation.Event.Name = flowevents.ScheduleEventName
	scheduleInvocation.Event.Ghe = &flowevents.ScheduleEvent{}

	jsonBody, err := json.Marshal(scheduleInvocation)
	require.NoError(t, err)

	var invocation Invocation
	err = json.Unmarshal(jsonBody, &invocation)
	require.NoError(t, err)

	assert.Equal(t, scheduleInvocation, invocation)
}

func Test_RoundtripMarshalInvocation_WithDynamicEvent(t *testing.T) {
	dynamicGhe := &flowevents.DynamicEvent{
		Workflow: "name: dynamic workflow\n  on: dynamic\n  steps:",
		Ref:      "refs/heads/master",
		Inputs:   map[string]string{"name": "monalisa"},
	}

	dynamicEventPayloadBody, err := json.Marshal(dynamicGhe)
	require.NoError(t, err)

	dynamicInvocation := NewInvocation(InvokingEvent{
		Name:    flowevents.Dynamic,
		Ghe:     dynamicGhe,
		Payload: dynamicEventPayloadBody,
	}, actor, actor, pushTarget)

	jsonBody, err := json.Marshal(dynamicInvocation)
	require.NoError(t, err)

	var invocation Invocation
	err = json.Unmarshal(jsonBody, &invocation)
	require.NoError(t, err)

	assert.Equal(t, dynamicInvocation.Event, invocation.Event)
}
