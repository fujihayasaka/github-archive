package proto

import (
	"golang.org/x/xerrors"
)

// Attribute returns the value (or values) of an attribute if present in the request.
// - if only present once, the value is returned
// - if no value is present, nil is returned
// - if more than one attribute with the same name is present, an error is returned
//
// The boolean argument indicates if the attribute existed in the request.
// This is necessary to distinguish when the attribute did not exist or existed but was explicitly nil
func (m *Request) Attribute(name string) (interface{}, bool, error) {
	if c := m.countFor(name); c > 1 {
		return nil, false, xerrors.Errorf("Expected only 1 attribute %s, found %d", name, c)
	}

	if value := m.firstValueFor(name); value != nil {
		result, err := value.Unwrap()
		return result, true, err
	}

	return nil, false, nil
}

// AttributesMap transforms Request.Attributes into a map[string]interface{}
func (m *Request) AttributesMap() (map[string]interface{}, error) {
	attrs := make(map[string]interface{})
	for _, a := range m.GetAttributes() {
		unwrappedValue, err := a.GetValue().Unwrap()
		if err != nil {
			return nil, err
		}
		attrs[a.GetId()] = unwrappedValue
	}

	return attrs, nil
}
func (m *Request) IsDebug() bool {
	if m == nil {
		return false
	}
	_, present, err := m.Attribute("_debug_")

	if err != nil || !present {
		return false
	}

	return true
}

// firstValueFor returns the value of an attribute if present in the request, nil otherwise
func (m *Request) firstValueFor(name string) *Value {
	for _, a := range m.GetAttributes() {
		if a.GetId() == name {
			return a.GetValue()
		}
	}
	return nil
}

// countFor returns how many times an attribute with a given ID is present in the request
func (m *Request) countFor(name string) int {
	result := 0
	for _, a := range m.GetAttributes() {
		if a.GetId() == name {
			result++
		}
	}
	return result
}

// Unwrap converts a authzd.Value kind (a protobuf one_of), into the value it contains.
// Returns inerface{}, either nil, a bool, an int64, a double, a String or an slice of the former.
func (m *Value) Unwrap() (interface{}, error) {
	switch valType := m.GetKind().(type) {
	case *Value_NullValue, nil:
		return nil, nil
	case *Value_BoolValue:
		return valType.BoolValue, nil
	case *Value_IntegerValue:
		return valType.IntegerValue, nil
	case *Value_DoubleValue:
		return valType.DoubleValue, nil
	case *Value_StringValue:
		return valType.StringValue, nil
	case *Value_IntegerListValue:
		return valType.IntegerListValue.GetValues(), nil
	case *Value_StringListValue:
		return valType.StringListValue.GetValues(), nil
	default:
		return nil, xerrors.Errorf("%T is an unknown protocol buffers type", valType)
	}
}

// NewNullValue creates a Value structure containing a NullValue
func NewNullValue() *Value {
	return &Value{
		Kind: &Value_NullValue{},
	}
}

// NewBoolValue creates a Value structure from the given bool
func NewBoolValue(b bool) *Value {
	return &Value{
		Kind: &Value_BoolValue{
			BoolValue: b,
		},
	}
}

// NewInt64Value creates a Value structure from the given int64
func NewInt64Value(i int64) *Value {
	return &Value{
		Kind: &Value_IntegerValue{
			IntegerValue: i,
		},
	}
}

// NewDoubleValue creates a Value structure from the given double
func NewDoubleValue(d float64) *Value {
	return &Value{
		Kind: &Value_DoubleValue{
			DoubleValue: d,
		},
	}
}

// NewStringValue creates a Value structure from the given string
func NewStringValue(s string) *Value {
	return &Value{
		Kind: &Value_StringValue{
			StringValue: s,
		},
	}
}

// NewStringListValue creates a Value structure from the given list of strings
func NewStringListValue(values ...string) *Value {
	return &Value{
		Kind: &Value_StringListValue{
			StringListValue: &StringList{Values: values},
		},
	}
}

// NewIntegerListValue creates a Value structure from the given list of strings
func NewIntegerListValue(values ...int64) *Value {
	return &Value{
		Kind: &Value_IntegerListValue{
			IntegerListValue: &IntegerList{Values: values},
		},
	}
}
