package tracing

import (
	"path"
	"runtime"
	"strings"
)

type callerInfo struct {
	Package      string
	TypeName     string
	FunctionName string
}

// operationName returns the name of the operation that should be used for a span
// skip is the number of frames to skip up the stack
// opFuncName is an optional string that can be used to override the function operation name
func operationName(skip int, opFuncName string) string {
	c := caller(skip + 1)
	if c == nil {
		return "<unknown>"
	}

	n := namespace(c)
	if opFuncName != "" {
		return n + opFuncName
	}

	return n + c.FunctionName
}

func namespace(c *callerInfo) string {
	if c.TypeName == "" {
		return c.Package + "/"
	}
	return c.Package + "/" + c.TypeName + "."
}

// caller returns info about the function skip+1 frames up the stack
func caller(skip int) *callerInfo {
	// 1 means get the call frame of the function that called this one
	pc, _, _, ok := runtime.Caller(skip + 1)
	if !ok {
		// this should never happen unless we're calling this via some weird reflection-based evaluation
		return nil
	}

	signature := path.Base(runtime.FuncForPC(pc).Name())

	i := strings.Index(signature, ".")
	if i == -1 {
		return &callerInfo{
			FunctionName: signature,
		}
	}

	pkg := signature[:i]
	signature = signature[i+1:]

	i = strings.Index(signature, ".")
	if i == -1 {
		return &callerInfo{
			Package:      pkg,
			TypeName:     "",
			FunctionName: signature,
		}
	}

	return &callerInfo{
		Package:      pkg,
		TypeName:     signature[:i],
		FunctionName: signature[i+1:],
	}
}
