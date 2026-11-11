package experiments

import (
	"context"
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestKVExperiments(t *testing.T) {
	ctx := context.Background()

	require.Empty(t, ctx, GetExperiments(ctx))

	ctx = WithExperiments(ctx, Experiments{"a": "b"})
	require.Equal(t, "b", GetExperiments(ctx)["a"])

	ctx = WithExperiment(ctx, "1", "2")
	require.Equal(t, "b", GetExperiments(ctx)["a"])
	require.Equal(t, "2", GetExperiments(ctx)["1"])

	ctx = WithExperimentEnabled(ctx, "exp")
	require.True(t, IsExperimentEnabled(ctx, "exp"))
	v, ok := GetExperiment(ctx, "exp")
	require.True(t, ok)
	require.Equal(t, "1", v)

	ctx = WithExperimentsEnabled(ctx, []string{"exp2", "exp3"})
	require.True(t, IsExperimentEnabled(ctx, "exp2"))
	require.True(t, IsExperimentEnabled(ctx, "exp3"))

	// Explicitly override experiment to be disabled
	ctx = WithExperiment(ctx, "exp4", Disabled)
	require.False(t, IsExperimentEnabled(ctx, "exp4"))

	// But the experiment does exist and has a value!
	v, hasExp4 := GetExperiment(ctx, "exp4")
	require.True(t, hasExp4)
	require.Equal(t, Disabled, v)
}

func TestSerDe(t *testing.T) {
	tests := []string{"", "a=", "a=b", "a=b,x=y"}
	for _, test := range tests {
		a := deserialize(test)
		b, err := a.serialize()
		require.NoError(t, err)
		require.Equal(t, test, b)
		require.EqualValues(t, a, deserialize(b))
	}
}

func TestSorting(t *testing.T) {
	raw, err := Experiments{"b": "1", "a": "1"}.serialize()
	require.NoError(t, err)
	require.Equal(t, "a=1,b=1", raw)
}

func TestSerializationErrors(t *testing.T) {
	_, err := Experiments{"=": "1"}.serialize()
	require.EqualError(t, err, `invalid experiment key: "="`)
	_, err = Experiments{",": "1"}.serialize()
	require.EqualError(t, err, `invalid experiment key: ","`)

	_, err = Experiments{"a": "="}.serialize()
	require.EqualError(t, err, `invalid experiment value: "="`)
	_, err = Experiments{"a": ","}.serialize()
	require.EqualError(t, err, `invalid experiment value: ","`)

	require.Equal(t, Experiments{}, deserialize("="))
	require.Equal(t, Experiments{}, deserialize(",,"))
	require.Equal(t, Experiments{}, deserialize("=,"))
	require.Equal(t, Experiments{}, deserialize("a,="))
}

func TestTooBig(t *testing.T) {
	e := Experiments{}
	for i := 0; i < 50; i++ {
		e[fmt.Sprintf("key%d", i)] = "enabled"
	}
	_, err := e.serialize()
	require.EqualError(t, err, "serialized experiments exceeds max length of 512 bytes: len=689")
}

func TestEqual(t *testing.T) {
	var tests = []struct {
		a     Experiments
		b     Experiments
		equal bool
	}{
		{
			a:     Experiments{},
			b:     Experiments{},
			equal: true,
		},
		{
			a:     Experiments{"a": "1"},
			b:     Experiments{"a": "1"},
			equal: true,
		},
		{
			a:     Experiments{"a": "1"},
			b:     Experiments{"a": "1", "b": "2"},
			equal: false,
		},
		{
			a:     Experiments{"a": "1", "b": "3"},
			b:     Experiments{"a": "1", "b": "2"},
			equal: false,
		},
	}

	for _, test := range tests {
		t.Run(fmt.Sprintf("%s = %s", test.a, test.b), func(t *testing.T) {
			require.True(t, test.a.Equal(test.a), "should equal itself")
			require.True(t, test.b.Equal(test.b), "should equal itself")
			require.Equal(t, test.equal, test.a.Equal(test.b))
			require.Equal(t, test.equal, test.b.Equal(test.a))

		})
	}
}
