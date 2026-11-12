package kvp

import (
	"fmt"
	"time"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

const nilString = "<nil>"

// Field is the type you should use to log dynamic values.
//
// A Field is a marshaling operation used to add a key-value pair to a logger's context. Most fields
// are lazily marshaled, so it's inexpensive to add fields to disabled debug-level log statements.
type Field = zapcore.Field

// Any takes a key and an arbitrary value and chooses the best way to represent them as a field,
// falling back to a reflection-based approach only if necessary.
//
// Since byte/uint8 and rune/int32 are aliases, Any can't differentiate between them. To minimize
// surprises, []byte values are treated as binary blobs, byte values are treated as uint8, and runes are always treated as integers.
func Any(key string, value interface{}) Field {
	return zap.Any(key, value)
}

// Binary constructs a field that carries an opaque binary blob.
//
// Binary data is serialized in an encoding-appropriate format. For example, zap's JSON encoder
// base64-encodes binary blobs. To log UTF-8 encoded text, use ByteString.
func Binary(key string, value []byte) Field {
	return zap.Binary(key, value)
}

// Bool constructs a field that carries a bool.
func Bool(key string, value bool) Field {
	return zap.Bool(key, value)
}

// Boolp constructs a field that carries a *bool. The returned Field will safely and explicitly
// represent `nil` when appropriate.
func Boolp(key string, value *bool) Field {
	return zap.Boolp(key, value)
}

// Bools constructs a field that carries a slice of bools.
func Bools(key string, value []bool) Field {
	return zap.Bools(key, value)
}

// ByteString constructs a field that carries UTF-8 encoded text as a []byte. To log opaque binary
// blobs (which aren't necessarily valid UTF-8), use Binary.
func ByteString(key string, value []byte) Field {
	return zap.ByteString(key, value)
}

// ByteStrings constructs a field that carries a slice of []byte, each of which must be UTF-8
// encoded text.
func ByteStrings(key string, value [][]byte) Field {
	return zap.ByteStrings(key, value)
}

// Complex128 constructs a field that carries a complex number. Unlike most numeric fields, this
// costs an allocation (to convert the complex128 to interface{}).
func Complex128(key string, value complex128) Field {
	return zap.Complex128(key, value)
}

// Complex128p constructs a field that carries a *complex128. The returned Field will safely and
// explicitly represent `nil` when appropriate.
func Complex128p(key string, value *complex128) Field {
	return zap.Complex128p(key, value)
}

// Complex128s constructs a field that carries a slice of complex numbers.
func Complex128s(key string, value []complex128) Field {
	return zap.Complex128s(key, value)
}

// Complex64 constructs a field that carries a complex number. Unlike most numeric fields, this
// costs an allocation (to convert the complex64 to interface{}).
func Complex64(key string, value complex64) Field {
	return zap.Complex64(key, value)
}

// Complex64p constructs a field that carries a *complex64. The returned Field will safely and
// explicitly represent `nil` when appropriate.
func Complex64p(key string, value *complex64) Field {
	return zap.Complex64p(key, value)
}

// Complex64s constructs a field that carries a slice of complex numbers.
func Complex64s(key string, value []complex64) Field {
	return zap.Complex64s(key, value)
}

// Duration constructs a field with the given key and value. The encoder controls how the duration
// is serialized.
func Duration(key string, value time.Duration) Field {
	return zap.Duration(key, value)
}

// Durationp constructs a field that carries a *time.Duration. The returned Field will safely and
// explicitly represent `nil` when appropriate.
func Durationp(key string, value *time.Duration) Field {
	return zap.Durationp(key, value)
}

// Durations constructs a field that carries a slice of time.Durations.
func Durations(key string, value []time.Duration) Field {
	return zap.Durations(key, value)
}

// Err constructs a field with the required semantic name "exception.message" and
// the value of the error as a string.
//
// You may prefer to use WithError(err) to track more information, but this
// Field can be used to ease porting from github/go-kvp.
func Err(err error) Field {
	errMsg := nilString
	if err != nil {
		errMsg = err.Error()
	}
	return zap.String("exception.message", errMsg)
}

// Float32 constructs a field that carries a float32. The way the floating-point value is
// represented is encoder-dependent, so marshaling is necessarily lazy.
func Float32(key string, value float32) Field {
	return zap.Float32(key, value)
}

// Float32p constructs a field that carries a *float32. The returned Field will safely and
// explicitly represent `nil` when appropriate.
func Float32p(key string, value *float32) Field {
	return zap.Float32p(key, value)
}

// Float32s constructs a field that carries a slice of floats.
func Float32s(key string, value []float32) Field {
	return zap.Float32s(key, value)
}

// Float64 constructs a field that carries a float64. The way the floating-point value is
// represented is encoder-dependent, so marshaling is necessarily lazy.
func Float64(key string, value float64) Field {
	return zap.Float64(key, value)
}

// Float64p constructs a field that carries a *float64. The returned Field will safely and explicitly represent `nil` when appropriate.
func Float64p(key string, value *float64) Field {
	return zap.Float64p(key, value)
}

// Float64s constructs a field that carries a slice of floats.
func Float64s(key string, value []float64) Field {
	return zap.Float64s(key, value)
}

// Int constructs a field with the given key and value.
func Int(key string, value int) Field {
	return zap.Int(key, value)
}

// Intp constructs a field that carries a *int. The returned Field will safely and explicitly
// represent `nil` when appropriate.
func Intp(key string, value *int) Field {
	return zap.Intp(key, value)
}

// Ints constructs a field that carries a slice of integers.
func Ints(key string, value []int) Field {
	return zap.Ints(key, value)
}

// Int16 constructs a field with the given key and value.
func Int16(key string, value int16) Field {
	return zap.Int16(key, value)
}

// Int16p constructs a field that carries a *int16. The returned Field will safely and explicitly
// represent `nil` when appropriate.
func Int16p(key string, value *int16) Field {
	return zap.Int16p(key, value)
}

// Int16s constructs a field that carries a slice of integers.
func Int16s(key string, value []int16) Field {
	return zap.Int16s(key, value)
}

// Int32 constructs a field with the given key and value.
func Int32(key string, value int32) Field {
	return zap.Int32(key, value)
}

// Int32p constructs a field that carries a *int32. The returned Field will safely and explicitly
// represent `nil` when appropriate.
func Int32p(key string, value *int32) Field {
	return zap.Int32p(key, value)
}

// Int32s constructs a field that carries a slice of integers.
func Int32s(key string, value []int32) Field {
	return zap.Int32s(key, value)
}

// Int64 constructs a field with the given key and value.
func Int64(key string, value int64) Field {
	return zap.Int64(key, value)
}

// Int64p constructs a field that carries a *int64. The returned Field will safely and explicitly
// represent `nil` when appropriate.
func Int64p(key string, value *int64) Field {
	return zap.Int64p(key, value)
}

// Int64s constructs a field that carries a slice of integers.
func Int64s(key string, value []int64) Field {
	return zap.Int64s(key, value)
}

// Int8 constructs a field with the given key and value.
func Int8(key string, value int8) Field {
	return zap.Int8(key, value)
}

// Int8p constructs a field that carries a *int8. The returned Field will safely and explicitly
// represent `nil` when appropriate.
func Int8p(key string, value *int8) Field {
	return zap.Int8p(key, value)
}

// Int8s constructs a field that carries a slice of integers.
func Int8s(key string, value []int8) Field {
	return zap.Int8s(key, value)
}

// Stack constructs a field that stores a stacktrace of the current goroutine under provided key.
// Keep in mind that taking a stacktrace is eager and expensive (relatively speaking); this function
// both makes an allocation and takes about two microseconds.
func Stack(key string) Field {
	return zap.StackSkip(key, 1) // don't include *this* function in the stack trace
}

// StackSkip constructs a field similarly to Stack, but also skips the given number of frames from
// the top of the stacktrace.
func StackSkip(key string, skip int) Field {
	return zap.StackSkip(key, skip+1) // don't include *this* function in the stack trace
}

// String constructs a field with the given key and value.
func String(key, value string) Field {
	return zap.String(key, value)
}

// Stringp constructs a field that carries a *string. The returned Field will safely and explicitly
// represent `nil` when appropriate.
func Stringp(key string, value *string) Field {
	return zap.Stringp(key, value)
}

// Strings constructs a field that carries a slice of strings.
func Strings(key string, value []string) Field {
	return zap.Strings(key, value)
}

// Stringer constructs a field with the given key and the output of the value's String method. The
// Stringer's String method is called lazily.
func Stringer(key string, value fmt.Stringer) Field {
	return zap.Stringer(key, value)
}

// Time constructs a Field with the given key and value. The encoder controls how the time is
// serialized.
func Time(key string, value time.Time) Field {
	return zap.Time(key, value)
}

// Timep constructs a field that carries a *time.Time. The returned Field will safely and explicitly
// represent `nil` when appropriate.
func Timep(key string, value *time.Time) Field {
	return zap.Timep(key, value)
}

// Times constructs a field that carries a slice of time.Times.
func Times(key string, value []time.Time) Field {
	return zap.Times(key, value)
}

// Uint constructs a field with the given key and value.
func Uint(key string, value uint) Field {
	return zap.Uint(key, value)
}

// Uintp constructs a field that carries a *uint. The returned Field will safely and explicitly
// represent `nil` when appropriate.
func Uintp(key string, value *uint) Field {
	return zap.Uintp(key, value)
}

// Uints constructs a field that carries a slice of unsigned integers.
func Uints(key string, value []uint) Field {
	return zap.Uints(key, value)
}

// Uint16 constructs a field with the given key and value.
func Uint16(key string, value uint16) Field {
	return zap.Uint16(key, value)
}

// Uint16p constructs a field that carries a *uint16. The returned Field will safely and explicitly
// represent `nil` when appropriate.
func Uint16p(key string, value *uint16) Field {
	return zap.Uint16p(key, value)
}

// Uint16s constructs a field that carries a slice of unsigned integers.
func Uint16s(key string, value []uint16) Field {
	return zap.Uint16s(key, value)
}

// Uint32 constructs a field with the given key and value.
func Uint32(key string, value uint32) Field {
	return zap.Uint32(key, value)
}

// Uint32p constructs a field that carries a *uint32. The returned Field will safely and explicitly
// represent `nil` when appropriate.
func Uint32p(key string, value *uint32) Field {
	return zap.Uint32p(key, value)
}

// Uint32s constructs a field that carries a slice of unsigned integers.
func Uint32s(key string, value []uint32) Field {
	return zap.Uint32s(key, value)
}

// Uint64 constructs a field with the given key and value.
func Uint64(key string, value uint64) Field {
	return zap.Uint64(key, value)
}

// Uint64p constructs a field that carries a *uint64. The returned Field will safely and explicitly
// represent `nil` when appropriate.
func Uint64p(key string, value *uint64) Field {
	return zap.Uint64p(key, value)
}

// Uint64s constructs a field that carries a slice of unsigned integers.
func Uint64s(key string, value []uint64) Field {
	return zap.Uint64s(key, value)
}

// Uint8 constructs a field with the given key and value.
func Uint8(key string, value uint8) Field {
	return zap.Uint8(key, value)
}

// Uint8p constructs a field that carries a *uint8. The returned Field will safely and explicitly
// represent `nil` when appropriate.
func Uint8p(key string, value *uint8) Field {
	return zap.Uint8p(key, value)
}

// Uint8s constructs a field that carries a slice of unsigned integers.
func Uint8s(key string, value []uint8) Field {
	return zap.Uint8s(key, value)
}

// Uintptr constructs a field with the given key and value.
func Uintptr(key string, value uintptr) Field {
	return zap.Uintptr(key, value)
}

// Uintptrp constructs a field that carries a *uintptr. The returned Field will safely and
// explicitly represent `nil` when appropriate.
func Uintptrp(key string, value *uintptr) Field {
	return zap.Uintptrp(key, value)
}

// Uintptrs constructs a field that carries a slice of pointer addresses.
func Uintptrs(key string, value []uintptr) Field {
	return zap.Uintptrs(key, value)
}
