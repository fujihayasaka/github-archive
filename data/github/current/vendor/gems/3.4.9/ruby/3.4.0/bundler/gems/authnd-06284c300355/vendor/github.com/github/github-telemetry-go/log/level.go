package log

type Level struct {
	level string
}

var (
	DebugLevel = Level{"debug"}
	InfoLevel  = Level{"info"}
	WarnLevel  = Level{"warn"}
	ErrorLevel = Level{"error"}
	FatalLevel = Level{"fatal"}
)

// String returns the string representation for Level
//
// This is useful when trying to get the string values for Level and mapping level in other external libraries. For example:
// ```
// trace.SetLogLevel(kvp.String("loglevel", log.DebugLevel.String())
// ```
func (l Level) String() string {
	return l.level
}
