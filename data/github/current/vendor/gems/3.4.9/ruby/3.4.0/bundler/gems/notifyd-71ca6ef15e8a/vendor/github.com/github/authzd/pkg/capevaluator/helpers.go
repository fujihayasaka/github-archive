// This file is inspired by proto/helpers.go for the authorizer proto
package capevaluator

import (
	authorizerpbhelpers "github.com/github/authzd/pkg/proto"
	"golang.org/x/xerrors"
)

// Attribute returns the value (or values) of an attribute if present in the request.
// - if only present once, the value is returned
// - if no value is present, nil is returned
// - if more than one attribute with the same name is present, an error is returned
//
// The boolean argument indicates if the attribute existed in the request.
// This is necessary to distinguish when the attribute did not exist or existed but was explicitly nil
func (m *SingleResourceRequest) Attribute(name string) (interface{}, bool, error) {
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
func (m *SingleResourceRequest) AttributesMap() (map[string]interface{}, error) {
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

func (m *SingleResourceRequest) IsDebug() bool {
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
func (m *SingleResourceRequest) firstValueFor(name string) *authorizerpbhelpers.Value {
	for _, a := range m.GetAttributes() {
		if a.GetId() == name {
			return a.GetValue()
		}
	}
	return nil
}

// countFor returns how many times an attribute with a given ID is present in the request
func (m *SingleResourceRequest) countFor(name string) int {
	result := 0
	for _, a := range m.GetAttributes() {
		if a.GetId() == name {
			result++
		}
	}
	return result
}
