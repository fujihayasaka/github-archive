package assertions

import (
	"fmt"
	"reflect"
	"strings"
	"sync"

	"github.com/github/billing-platform/lib/models"
	"github.com/onsi/gomega/types"
	"github.com/petergtz/pegomock/v4"
)

type includesMatcher struct {
	expected interface{}
	errors   []string
}

func IncludeItem(expected interface{}) types.GomegaMatcher {
	return &includesMatcher{
		expected: expected,
		errors:   []string{},
	}
}

func (matcher *includesMatcher) FailureMessage(actual interface{}) (message string) {
	return fmt.Sprintf("Actual and expected did not match:\n%s", strings.Join(matcher.errors, "\n"))
}

func (matcher *includesMatcher) NegatedFailureMessage(actual interface{}) (message string) {
	return fmt.Sprintf("Actual and expected did not match:\n%s", strings.Join(matcher.errors, "\n"))
}

func (matcher *includesMatcher) Match(actual interface{}) (success bool, err error) {
	actualTypeOf := reflect.TypeOf(actual)
	expectedTypeOf := reflect.TypeOf(matcher.expected)

	if actualTypeOf.Kind() != reflect.Slice {
		return false, fmt.Errorf("expected slice, got %s", actualTypeOf.Kind())
	}

	if expectedTypeOf.Kind() != reflect.Func {
		return false, fmt.Errorf("expected function, got %s", expectedTypeOf.Kind())
	}

	if expectedTypeOf.NumIn() != 1 {
		return false, fmt.Errorf("expected function with 1 input, got %d", expectedTypeOf.NumIn())
	}

	if expectedTypeOf.NumOut() != 1 {
		return false, fmt.Errorf("expected function with 1 output, got %d", expectedTypeOf.NumOut())
	}

	if expectedTypeOf.Out(0).Kind() != reflect.Bool {
		return false, fmt.Errorf("expected function with bool output, got %s", expectedTypeOf.Out(0).Kind())
	}

	if actualTypeOf.Elem() != expectedTypeOf.In(0) {
		return false, fmt.Errorf("expected function with input of %s, got %s", actualTypeOf.Elem(), expectedTypeOf.In(0))
	}

	av := reflect.ValueOf(actual)
	ev := reflect.ValueOf(matcher.expected)

	for i := 0; i < av.Len(); i++ {
		actualValue := av.Index(i).Interface()
		expectedValue := ev.Call([]reflect.Value{reflect.ValueOf(actualValue)})[0].Interface()

		if expectedValue.(bool) {
			return true, nil
		}
	}

	return false, fmt.Errorf("Did not find match in actual")

}

type Keymatcher struct {
	Value  pegomock.Param
	actual pegomock.Param

	sync.Mutex
}

func (matcher *Keymatcher) Matches(param pegomock.Param) bool {
	matcher.Lock()
	defer matcher.Unlock()

	value := matcher.Value.(models.ItemKey)
	if value == nil {
		return false
	}
	actual := param.(models.ItemKey)
	matcher.actual = actual
	if actual == nil {
		return false
	}

	return reflect.DeepEqual(value.GetKey(), actual.GetKey())
}

func (matcher *Keymatcher) FailureMessage() string {
	return fmt.Sprintf("KeyMatcher -------------------------------: %v; but got: %v", matcher.Value, matcher.actual)
}

func (matcher *Keymatcher) String() string {
	return fmt.Sprintf("KeyMatcher -------------------------------:(%#v)", matcher.Value)
}

func ItemKeyEq(value models.ItemKey) *Keymatcher {
	return &Keymatcher{Value: value}
}
