package mysql

import "context"

// Callback represents a callback function.
type Callback[T any] func(context.Context) (T, error)

// CallbackNoReturn represents a callback function that doesn't return anything.
type CallbackNoReturn func(context.Context) error

// ToCallback adapts a CallbackNoReturn, that is, a function that only returns an error,
// into a Callback[interface{}], that is, a function that returns an empty interface and an error.
// This is done so the function can be used with functions like WithRetries and WithThrottling
func ToCallback(fn CallbackNoReturn) Callback[interface{}] {
	return func(ctx context.Context) (interface{}, error) {
		var ret interface{}
		return ret, fn(ctx)
	}
}
