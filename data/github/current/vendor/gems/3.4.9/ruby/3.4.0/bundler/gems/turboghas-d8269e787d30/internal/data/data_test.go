package data_test

import (
	"testing"

	"github.com/github/go-stats"
	"github.com/github/turboghas/internal/mocks"
	"github.com/stretchr/testify/mock"
)

type mockCounter struct {
	stats.NullClient
	mock.Mock
}

func (e *mockCounter) Counter(key string, tags stats.Tags, value int64) {
	e.Mock.Called(key, tags, value)
}

func (e *mockCounter) WithTags(tags stats.Tags) stats.Client {
	e.Mock.Called(tags)
	return e
}

var _ stats.Client = &mockCounter{}

func expectCounter(key string) func(t *testing.T, table string) stats.Client {
	return func(t *testing.T, table string) stats.Client {
		t.Helper()
		c := mocks.Cleanup(t, &mockCounter{})
		c.On("Counter", key, stats.Tags(nil), int64(1))
		c.On("WithTags", stats.Tags{"table": table})
		return c
	}
}

var expectInsert = expectCounter("data.insert")
var expectUpdate = expectCounter("data.update")
var expectMatch = expectCounter("data.match")
