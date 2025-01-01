package o11y

import (
	"path"
	"runtime"
	"strings"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// setSpanNameFromCaller sets the span name to the name of the calling function.
// This function tries to mimic the convention from https://github.com/github/go-trace/blob/main/span.go.
// It also assigns attributes for the location of the function call.
func setSpanNameAndAttributesFromCaller(span trace.Span, operationName string, skip int) {
	// Get caller info
	pkg, typeName, funcName, fileName, lineNumber := callerInfo(skip + 1)
	operation := opname(pkg, typeName, funcName)

	if operationName == "" {
		span.SetName(operation)
	}

	span.SetAttributes(
		attribute.String("code.function", funcName),
		attribute.String("code.namespace", namespace(pkg, typeName)),
		attribute.String("code.filepath", fileName),
		attribute.Int("code.lineno", lineNumber),
	)
}

func namespace(pkg, typeName string) string {
	// fully qualified package paths are long, we only use the actual package's
	// name in the operation name
	pkg = path.Base(pkg)
	if typeName != "" {
		return pkg + "/" + typeName
	}
	return pkg
}

func opname(pkg, typeName, funcName string) string {
	namespace := namespace(pkg, typeName)
	return namespace + "." + funcName
}

func callerInfo(skip int) (pkg, typeName, funcName, filename string, line int) {
	pc, file, line, ok := runtime.Caller(skip + 1)
	if !ok {
		return "no_debug_info", "no_debug_info", "no_debug_info", "no_debug_info", 0
	}
	fn := runtime.FuncForPC(pc)
	signature := fn.Name()

	// in any case, make sure we return something useful
	funcName = signature

	// then try to extract pkg, type and func/method names
	// we only care about the last part of the package's path
	pkgPrefix, signature := path.Split(signature)

	// the first `.` after the last `/` is the package prefix
	if i := strings.Index(signature, "."); i >= 0 { // nolint:gocritic
		pkg, signature = pkgPrefix+signature[:i], signature[i+1:]
		typeName = ""
		funcName = signature
	}
	// if there's a second `.` after that, it's a method on a type
	if i := strings.Index(signature, "."); i >= 0 { // nolint:gocritic
		typeName = signature[:i]
		funcName = signature[i+1:]
	}

	return pkg, typeName, funcName, file, line
}
