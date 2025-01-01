package common

type QueryResult[T any] struct {
	Items      []T
	TotalItems uint64
	More       bool
}
