package kvp

import (
	"fmt"
	"math"
	"strconv"
	"time"
)

type ValueType byte

const (
	BoolType     ValueType = 'b'
	IntType      ValueType = 'i'
	UintType     ValueType = 'u'
	FloatType    ValueType = 'f'
	DurationType ValueType = 'd'
	TimeType     ValueType = 't'
	StringType   ValueType = 's'
	AnyType      ValueType = 'a'
	LazyType     ValueType = 'l'
	ErrorType    ValueType = 'e'
	CallInfoType ValueType = 'C'

	nilString string = "<nil>"
)

// Field is a generic type that stores a key-value pair entry to be
// formatted with the log message.
type Field struct {
	// To keep Field small, avoid adding a new field if an existing one is capable
	// of representing the value without loss or additional allocation.

	// Key is the name of the key-value pair
	Key string

	// String is the string value of this entry, if the entry is a string
	Str string

	// Int is the numerical value of the entry, if the entry is a number
	Int int64

	// Any stores any other kind of values as an empty interface
	Any interface{}

	// Boolean is the boolean value of the entry, if the entry is a boolean
	Boolean bool

	// T is the type tag for this log Field
	T ValueType
}

// String creates a Field that stores an string value
func String(key, val string) Field {
	return Field{T: StringType, Key: key, Str: val}
}

// Stringer creates a Field that stores an string value based on the provided Stringer
func Stringer(key string, val fmt.Stringer) Field {
	return String(key, val.String())
}

// Bool creates a Field that stores a boolean value
func Bool(key string, val bool) Field {
	return Field{T: BoolType, Key: key, Boolean: val}
}

// Err creates a Field storing an error message. If the given
// error is nil, the field defaults to the undecorated string, "<nil>"
func Err(val error) Field {
	errMsg := nilString
	if val != nil {
		errMsg = val.Error()
	}
	return Field{T: ErrorType, Key: "error", Str: errMsg, Any: val}
}

// Int creates a Field that stores an int value
func Int(key string, val int) Field {
	return Field{T: IntType, Key: key, Int: int64(val)}
}

// Int64 creates a Field that stores an int64 value
func Int64(key string, val int64) Field {
	return Field{T: IntType, Key: key, Int: val}
}

// Uint creates a Field that stores an unsigned int value
func Uint(key string, val uint) Field {
	return Field{T: UintType, Key: key, Int: int64(val)}
}

// Uint64 creates a Field that stores an unsigned int64 value
func Uint64(key string, val uint64) Field {
	return Field{T: UintType, Key: key, Int: int64(val)}
}

// Float creates a Field that stores a float64 value
func Float(key string, val float64) Field {
	return Field{T: FloatType, Key: key, Int: int64(math.Float64bits(val))}
}

// Duration creates a Field that stores a time.Duration value
func Duration(key string, val time.Duration) Field {
	return Field{T: DurationType, Key: key, Int: int64(val)}
}

// Time creates a Field that stores a time.Time value
func Time(key string, time time.Time) Field {
	return Field{T: TimeType, Key: key, Int: time.UnixNano()}
}

// Any creates a Field that can store any given value
func Any(key string, any interface{}) Field {
	return Field{T: AnyType, Key: key, Any: any}
}

// LazyLogger is a callback that returns a value lazily for logging
type LazyLogger func() interface{}

// Lazy creates a logging Field that only generates the logged value
// if the log entry is going to be logged. The logged value must be
// yielded by the given callback.
//
// This is specially useful for Debug logging of data that is expensive
// to calculate.
func Lazy(key string, log LazyLogger) Field {
	return Field{T: LazyType, Key: key, Any: log}
}

// CallInfo defines a field with runtime information about the call site for a
// particular logging call. When added to a logging call, the CallInfo field is
// printed in the log, with the given `key` and a value that is computed from
// the given `format` based on the location where the user is currently logging
// from. Note that this replacement is always performed at logging time, so
// CallInfo fields can be safely added to the fields of a Logger with
// `Logger.With`.
//
// `format` is an arbitrary string where the following special tokens will be
// replaced with the corresponding call information:
//
// - "{File}": the name of the current file.
// - "{Path}": the full path to the current file.
// - "{Line}": the line number for this logging call
// - "{Module}": the name of the current module
// - "{Struct}": the name of the struct acting as a receiver for the current
// method, or "" if you're logging from a global function
// - "{Method}": the name of the method being logged from, or "" if you're
// logging from a global function
// - "{Function}": the name of the current function being logged from, which
// will be either a global function, a struct method, or a closure
// - "{Namespace}": namespace is either the current struct receiver (when
// called from a method), or the current module, when called from a global
// function
func CallInfo(key string, format string) Field {
	return Field{T: CallInfoType, Key: key, Str: format}
}

// Value returns the raw value
func (f *Field) Value() interface{} {
	switch f.T {
	case IntType:
		return f.Int
	case UintType:
		return f.asUint()
	case FloatType:
		return f.AsFloat()
	case BoolType:
		return f.Boolean
	case DurationType:
		return f.AsDuration()
	case TimeType:
		return f.AsTime()
	case AnyType:
		return f.Any
	case LazyType:
		return f.LazyValue()
	case ErrorType:
		return f.Any
	default:
		return f.Str
	}
}

func (f *Field) asUint() uint64 {
	return uint64(f.Int)
}

// AsFloat returns the float64 value stored in this Field, if the Field is a float
func (f *Field) AsFloat() float64 {
	return math.Float64frombits(uint64(f.Int))
}

// AsDuration returns the time.Duration value stored in this field, if the field is a duration
func (f *Field) AsDuration() time.Duration {
	return time.Duration(f.Int)
}

// AsTime returns the time.Time duration stored in this field, if the field is a time
func (f *Field) AsTime() time.Time {
	return time.Unix(f.Int/1e9, f.Int%1e9)
}

// LazyValue returns the lazily-computated value stored in this field
func (f *Field) LazyValue() interface{} {
	return f.Any.(LazyLogger)()
}

// String returns the value stored in this field as a string, if it can be
// converted. This should be use sparingly and is only here until the haystack
// reporter takes a real context instead of a map[string]string.
func (f *Field) String() string {
	switch f.T {
	case IntType:
		return strconv.FormatInt(f.Int, 10)
	case UintType:
		return strconv.FormatUint(f.asUint(), 10)
	case FloatType:
		return strconv.FormatFloat(f.AsFloat(), 'E', -1, 64)
	case BoolType:
		return fmt.Sprintf("%t", f.Boolean)
	case DurationType:
		return f.AsDuration().String()
	case TimeType:
		return f.AsTime().Format("2006-01-02 15:04:05.999999999 -0700 MST")
	case AnyType:
		return fmtAnyStr(f.Any)
	default:
		return f.Str
	}
}

func fmtAnyStr(any interface{}) string {
	switch str := any.(type) {
	case fmt.Stringer:
		return str.String()
	case fmt.GoStringer:
		return str.GoString()
	default:
		return fmt.Sprint(str)
	}
}
