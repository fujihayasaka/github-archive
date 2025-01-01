// Attribute mappers are a set of helpers to convert zapcore fields to OpenTelemetry attributes.
//
// The helpers also include some usefull functions for filtering fields from the attributes list
// and providing some type conversions from field types to OpenTelemetry attribute types.
package kvp

import (
	"fmt"
	"math"
	"reflect"
	"time"

	"go.opentelemetry.io/otel/attribute"
	"go.uber.org/zap/zapcore"
)

// MapAttributes returns a list of attributes from fields
//
// The helper will accept a filterKeys parameter that will be used to filter out
// unwanted fields.
func MapAttributes(filterKeys map[string]struct{}, fields ...Field) []attribute.KeyValue {
	if len(filterKeys) == 0 {
		a := make([]attribute.KeyValue, 0, len(fields))
		for _, f := range fields {
			a = append(a, AttributeMapper(f))
		}
		return a
	}
	a := make([]attribute.KeyValue, 0, len(fields)-len(filterKeys))
	for _, f := range fields {
		if _, isIgnored := filterKeys[f.Key]; !isIgnored {
			a = append(a, AttributeMapper(f))
		}
	}
	return a
}

// AttributeMapper is converting zapcore fields to OpenTelemtry attribute.KeyValue
//
// We look at all the Field types in the zapcore package and map them to their corresponding OpenTelemetry attribute type
// For a list of all availabe Field types look at type FieldType uint8 in `zapcore/field.go`
// We are mainly intrested in the types that kvp.go will expose.
func AttributeMapper(f Field) attribute.KeyValue {
	switch f.Type {
	case zapcore.ArrayMarshalerType:
		return mapAttributeSlice(f)
	case zapcore.BinaryType,
		zapcore.ByteStringType,
		zapcore.Complex64Type,
		zapcore.Complex128Type,
		zapcore.ErrorType,
		zapcore.InlineMarshalerType,
		zapcore.ObjectMarshalerType,
		zapcore.ReflectType,  // like object but usually used in constructing an empty or nil value key
		zapcore.StringerType, // falls into attribute.Stringer for mapInterfaceAttributeString
		zapcore.TimeFullType: // this is a as is time that's value is outside of the range that can be represented as int64
		// Turn all these Interface based types into strings as they do not have OpenTelemetry equivalent
		return mapInterfaceAttributeString(f)
	case zapcore.StringType: // This is normal string to string type conversion
		return mapAttributeString(f)
	case zapcore.BoolType:
		return mapAttributeBool(f)
	case zapcore.Float64Type:
		return mapAttributeFloat64(f)
	case zapcore.Float32Type:
		return mapAttributeFloat32(f)
	case zapcore.DurationType,
		zapcore.Int64Type,
		zapcore.Int32Type,
		zapcore.Int16Type,
		zapcore.Int8Type,
		zapcore.Uint64Type, // NOTE: this is not a good idea to use uint64 for int64 because of overflow but zapcore already does this
		zapcore.Uint32Type,
		zapcore.Uint16Type,
		zapcore.Uint8Type,
		zapcore.UintptrType: // note: zapcore.Field.Uintptr is mapping this to Field.Integer as int64, otherwise nil pointers are ReflectType
		return mapAttributeInt(f)
	case zapcore.TimeType:
		return mapAttributeTime(f)
	case zapcore.NamespaceType,
		zapcore.SkipType:
		// everything else after this is empty attribute with key name but "" for value
		return mapEmptyAttribute(f)
	default:
		// These types have no value so lets return an empty string with the name
		return mapEmptyAttribute(f)
	}
}

// mapAttributeSlice converts Field.Interface to it's corresponding attribute.KeyValue type.
//
// The possible Field types are represented in zap/array.go
// so we only need to handle those that map to one of the
// supported Slice types for attribute
// `go.opentelemetry.io/otel/attribute/value.go` as:
//
//	[]bool - attribute.BoolSlice()
//	[]int - attribute.IntSlice
//	[]int64 - attribute.Int64Slice
//	[]float64 - attribute.Float64Slice
//	[]string - attribute.StringSlice
//
// All other zapcore Interface types will be represented as []string
func mapAttributeSlice(f Field) attribute.KeyValue {
	v := reflect.ValueOf(f.Interface)
	if v.Kind() != reflect.Slice { // it's not a slice, just return the result as a string
		return attribute.String(f.Key, fmt.Sprintf("%v", f.Interface))
	}
	if v.Len() == 0 { // it's a slice but it's empty, return empty []string
		return attribute.StringSlice(f.Key, make([]string, 0))
	}
	// we only map the types we can map directly to an attribute
	// otherwise we are working with string slices
	switch v.Index(0).Kind() {
	case reflect.Bool:
		return attribute.BoolSlice(f.Key, boolValues(v))
	case reflect.Int:
		return attribute.IntSlice(f.Key, intValues(v))
	case reflect.Int64, reflect.Int32, reflect.Int16, reflect.Int8:
		return attribute.Int64Slice(f.Key, int64Values(v))
	case reflect.Uint, reflect.Uint64, reflect.Uint32, reflect.Uint16, reflect.Uint8, reflect.Uintptr:
		return attribute.Int64Slice(f.Key, uint64Values(v))
	case reflect.Float32:
		return attribute.Float64Slice(f.Key, float32Values(v))
	case reflect.Float64:
		return attribute.Float64Slice(f.Key, float64Values(v))
	case reflect.String:
		return attribute.StringSlice(f.Key, stringValues(v))
	case reflect.TypeOf(time.Time{}).Kind():
		return attribute.Int64Slice(f.Key, timeValues(v))
	case reflect.TypeOf(time.Duration(0)).Kind():
		return attribute.Int64Slice(f.Key, durationValues(v))
	default:
		return attribute.StringSlice(f.Key, anyValueAsString(v)) // everything else is a []string
	}
}

// boolValues convert from reflect.Value to []bool, requires type checking for slice
func boolValues(v reflect.Value) []bool {
	vals := make([]bool, v.Len())
	for i := 0; i < v.Len(); i++ {
		vals[i] = v.Index(i).Bool()
	}
	return vals
}

// intValues convert from reflect.Value to []int, requires type checking for slice
func intValues(v reflect.Value) []int {
	vals := make([]int, v.Len())
	for i := 0; i < v.Len(); i++ {
		vals[i] = int(v.Index(i).Int())
	}
	return vals
}

// int64Values convert from reflect.Value to []int64, requires type checking for slice
func int64Values(v reflect.Value) []int64 {
	vals := make([]int64, v.Len())
	for i := 0; i < v.Len(); i++ {
		vals[i] = v.Index(i).Int()
	}
	return vals
}

// uint64Values convert from reflect.Value to []uint64, requires type checking for slice
func uint64Values(v reflect.Value) []int64 {
	vals := make([]int64, v.Len())
	for i := 0; i < v.Len(); i++ {
		vals[i] = int64(v.Index(i).Uint())
	}
	return vals
}

// float64Values convert from reflect.Value to []float64, requires type checking for slice
func float64Values(v reflect.Value) []float64 {
	vals := make([]float64, v.Len())
	for i := 0; i < v.Len(); i++ {
		vals[i] = v.Index(i).Float()
	}
	return vals
}

// float32Values convert from reflect.Value of []float32 to []float64, requires type checking for slice
func float32Values(v reflect.Value) []float64 {
	vals := make([]float64, v.Len())
	for i := 0; i < v.Len(); i++ {
		val := v.Index(i).Float()
		vals[i] = float64(val)
	}
	return vals
}

// stringValues convert from reflect.Value to []string, requires type checking for slice
func stringValues(v reflect.Value) []string {
	vals := make([]string, v.Len())
	for i := 0; i < v.Len(); i++ {
		vals[i] = v.Index(i).String()
	}
	return vals
}

// timeValues convert from reflect.Value to []int64, requires type checking for slice
func timeValues(v reflect.Value) []int64 {
	vals := make([]int64, v.Len())
	for i := 0; i < v.Len(); i++ {
		time := v.Index(i).Interface().(time.Time)
		vals[i] = time.UTC().UnixNano()
	}
	return vals
}

// durationValues convert from reflect.Value to []int64, requires type checking for slice
func durationValues(v reflect.Value) []int64 {
	vals := make([]int64, v.Len())
	for i := 0; i < v.Len(); i++ {
		vals[i] = int64(v.Index(i).Interface().(time.Duration))
	}
	return vals
}

// anyValueAsString convert from reflect.Value to []string, requires type checking for slice
func anyValueAsString(v reflect.Value) []string {
	vals := make([]string, v.Len())
	for i := 0; i < v.Len(); i++ {
		str, ok := v.Index(i).Interface().(fmt.Stringer)
		if ok {
			vals[i] = str.String()
		} else {
			vals[i] = fmt.Sprintf("%v", v.Index(i).Interface())
		}
	}
	return vals
}

// mapInterfaceAsString converts interface{} to string
func mapInterfaceAttributeString(f Field) attribute.KeyValue {
	str, ok := f.Interface.(fmt.Stringer) // check to see if the interface is a Stringer
	if ok {
		return attribute.Stringer(f.Key, str)
	}
	return attribute.String(f.Key, fmt.Sprintf("%v", f.Interface))
}

// mapEmptyAttribute(f Field) returns attribute.String with "" string value
// useful for mapping nil or zapcore Field with no values
func mapEmptyAttribute(f Field) attribute.KeyValue {
	return attribute.String(f.Key, "")
}

// mapAttributeString converts Field.String to Attribute.String
func mapAttributeString(f Field) attribute.KeyValue {
	return attribute.String(f.Key, f.String)
}

// mapAttributeBool converts Field.Bool to Attribute.Bool
func mapAttributeBool(f Field) attribute.KeyValue {
	if f.Integer == 1 {
		return attribute.Bool(f.Key, true)
	}
	return attribute.Bool(f.Key, false)
}

// mapAttributeFloat converts Field.Float64 to Attribute.Float64
// zapcore stores float64 as int64 which is converted from uint64 using math.Float64bits()
func mapAttributeFloat64(f Field) attribute.KeyValue {
	return attribute.Float64(f.Key, math.Float64frombits(uint64(f.Integer)))
}

// mapAttributeFloat converts Field.Float64 to Attribute.Float64
// zapcore stores float32 as int64 which is converted from uint32 using math.Float32bits()
// attribute only deals in storing float64 so we convert all float32 to float64
func mapAttributeFloat32(f Field) attribute.KeyValue {
	return attribute.Float64(f.Key, float64(math.Float32frombits(uint32(f.Integer))))
}

// mapAttributeInt converts Field.Integer to Attribute.Int64
func mapAttributeInt(f Field) attribute.KeyValue {
	return attribute.Int64(f.Key, f.Integer)
}

// mapAttributeTime converts Field.TimeType to Attribute.Int64
// note all times are converted to UTC time from original Field.Interface (time.Location)
// and stored in int64 representing the nanoseconds since epoch
func mapAttributeTime(f Field) attribute.KeyValue {
	local := f.Interface.(*time.Location)
	if local != nil {
		return attribute.Int64(f.Key, time.Unix(0, f.Integer).In(local).UTC().UnixNano())
	}
	return attribute.Int64(f.Key, time.Unix(0, f.Integer).UTC().UnixNano())
}
