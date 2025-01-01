package cocofix

import (
	"bytes"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestSanitizeJsonString(t *testing.T) {
	r := sanitizeJsonString("{\"diff\": \"test\"}")
	require.Equal(t, "{\"diff\": \"REDACTED\"}", r)

	r = sanitizeJsonString(`{"diff": "\"something personal"}`)
	require.Equal(t, "{\"diff\": \"REDACTED\"}", r)

	fixes := CocofixResponse{
		Output{
			Alert: respAlert{
				RuleId: "js/some-injection",
				Location: Location{
					Path:        "hello/world.js",
					StartLine:   10,
					StartColumn: 4,
					EndColumn:   10,
					EndLine:     10,
				},
			},
			Outcome: Outcome{
				Kind: "fix",
				Diffs: []Diff{
					{"hello/world.js", "test"},
					{"hello/two.js", "baz"},
				},
				Assessment: Assessment{
					Outcome: "valid",
				},
			},
		},
	}

	b, err := json.Marshal(fixes)
	require.NoError(t, err)
	r = sanitizeJsonString(string(b))
	// require.Equal(t, "{\"diff\": \"REDACTED\"}", r)
	err = json.Unmarshal([]byte(r), &fixes)
	require.NoError(t, err)
	require.Equal(t, "REDACTED", fixes[0].Outcome.Diffs[0].Diff)
	require.Equal(t, "REDACTED", fixes[0].Outcome.Diffs[1].Diff)
}

func TestLimitedCombinedOutput(t *testing.T) {
	stderr := bytes.NewBufferString("stderr7890")
	stdout := bytes.NewBufferString("stdout7890")
	truncateBuffers(11, stderr, stdout)
	require.Equal(t, "stderr7890", stderr.String())
	require.Equal(t, "s", stdout.String())

	stderr = bytes.NewBufferString("stderr7890")
	stdout = bytes.NewBufferString("stdout7890")
	truncateBuffers(6, stderr, stdout)
	require.Equal(t, "stderr", stderr.String())
	require.Equal(t, "", stdout.String())

	stderr = bytes.NewBufferString("stderr7890")
	stdout = bytes.NewBufferString("stdout7890")
	truncateBuffers(50, stderr, stdout)
	require.Equal(t, "stderr7890", stderr.String())
	require.Equal(t, "stdout7890", stdout.String())

	// non complete strings
	stderr = bytes.NewBuffer([]byte{97, 114, 116, 104, 117, 114, 110, 110})
	stdout = bytes.NewBuffer([]byte{0xF0, 0x9F, 0x98, 0x81})
	truncateBuffers(50, stderr, stdout)
	require.Equal(t, "arthurnn", stderr.String())
	require.Equal(t, "😁", stdout.String())

	stderr = bytes.NewBuffer([]byte{97, 114, 116, 104, 117, 114, 110, 110})
	stdout = bytes.NewBuffer([]byte{0xF0, 0x9F, 0x98, 0x81})
	truncateBuffers(10, stderr, stdout)
	require.Equal(t, "arthurnn", stderr.String())
	require.Equal(t, "\xf0\x9f", stdout.String())

	// three buffers
	stderr = bytes.NewBufferString("stderr7890")
	stdout = bytes.NewBufferString("stdout7890")
	stdin := bytes.NewBufferString("stdin7890")
	truncateBuffers(11, stderr, stdout, stdin)
	require.Equal(t, "stderr7890", stderr.String())
	require.Equal(t, "s", stdout.String())
	require.Equal(t, "", stdin.String())
}
