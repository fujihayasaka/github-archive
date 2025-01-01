package test_helpers

import (
	"fmt"
	"reflect"

	"go.uber.org/mock/gomock"
)

type pointerTargetMatcher struct {
	target interface{}
}

func (m pointerTargetMatcher) Matches(x interface{}) bool {
	if gomock.Nil().Matches(x) {
		return false
	}

	v := reflect.ValueOf(x)

	if v.Type().Kind() != reflect.Pointer {
		return false
	}

	return gomock.Eq(m.target).Matches(v.Elem().Interface())
}

func (m pointerTargetMatcher) String() string {
	return fmt.Sprintf("pointer to something that is equal to %v (%T)", m.target, m.target)
}

func PointerTo(x interface{}) gomock.Matcher {
	return pointerTargetMatcher{target: x}
}
