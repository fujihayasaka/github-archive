package tracing

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func normalFunc(skip int, f string) string {
	return operationName(skip, f)
}

type exampleStruct struct{}

func (e exampleStruct) valueReceiverFunc(skip int, f string) string {
	return operationName(skip, f)
}

func (e *exampleStruct) pointerReceiverFunc(skip int, f string) string {
	return operationName(skip, f)
}

func TestOperationName(t *testing.T) {
	tests := []struct {
		name     string
		testFunc func(int, string) string
		skip     int
		funcName string
		want     string
	}{
		{
			name:     "normal function",
			testFunc: normalFunc,
			want:     "tracing/normalFunc",
		},
		{
			name:     "normal function with override",
			testFunc: normalFunc,
			funcName: "override",
			want:     "tracing/override",
		},
		{
			name:     "struct value receiver functiom",
			testFunc: exampleStruct{}.valueReceiverFunc,
			want:     "tracing/exampleStruct.valueReceiverFunc",
		},
		{
			name:     "struct value receiver function with override",
			testFunc: exampleStruct{}.valueReceiverFunc,
			funcName: "override",
			want:     "tracing/exampleStruct.override",
		},
		{
			name:     "struct pointer receiver function",
			testFunc: (&exampleStruct{}).pointerReceiverFunc,
			want:     "tracing/(*exampleStruct).pointerReceiverFunc",
		},
		{
			name:     "struct pointer receiver function with override",
			testFunc: (&exampleStruct{}).pointerReceiverFunc,
			funcName: "override",
			want:     "tracing/(*exampleStruct).override",
		},
		{
			name: "anonymous function",
			testFunc: func(skip int, f string) string { //nolint:gocritic // Ignore unlambda
				return operationName(skip, f)
			},
			want: "tracing/TestOperationName.func1",
		},
		{
			name: "anonymous function with override",
			testFunc: func(skip int, f string) string { //nolint:gocritic // Ignore unlambda
				return operationName(skip, f)
			},
			funcName: "override",
			want:     "tracing/TestOperationName.override",
		},
		{
			name:     "function with skip",
			testFunc: normalFunc,
			skip:     1,
			want:     "tracing/TestOperationName.func3",
		},
		{
			name:     "function with skip and override",
			testFunc: normalFunc,
			skip:     1,
			funcName: "override",
			want:     "tracing/TestOperationName.override",
		},
		{
			name:     "invalid skip",
			testFunc: normalFunc,
			skip:     100,
			want:     "<unknown>",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.testFunc(tt.skip, tt.funcName)
			require.Equal(t, tt.want, got)
		})
	}
}
