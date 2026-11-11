package mock

import (
	"time"

	"github.com/github/go-stats"
	"github.com/stretchr/testify/mock"
)

type MockedStatter struct {
	mock.Mock
}

func (m *MockedStatter) Start() {
	m.Called()
}

func (m *MockedStatter) Run() {
	m.Called()
}

func (m *MockedStatter) Stop() {
	m.Called()
}

func (m *MockedStatter) Report(t stats.Type, key string, value float64, tags stats.Tags, rate float32) {
	m.Called(t, key, value, tags, rate)
}

func (m *MockedStatter) Event(title, text string, tags stats.Tags) {
	m.Called(title, text, tags)
}

func (m *MockedStatter) Gauge(key string, tags stats.Tags, value int64) {
	m.Called(key, tags, value)
}

type Tags = stats.Tags

func (m *MockedStatter) Counter(key string, tags Tags, value int64) {
	m.Called(key, tags, value)
}

func (m *MockedStatter) Increment(key string, tags stats.Tags) {
	m.Called(key, tags)
}

func (m *MockedStatter) Histogram(key string, tags stats.Tags, value int64) {
	m.Called(key, tags, value)
}

func (m *MockedStatter) Timing(key string, tags stats.Tags, value time.Duration) {
	m.Called(key, tags, value)
}

func (m *MockedStatter) Distribution(key string, tags stats.Tags, value float64) {
	m.Called(key, tags, value)
}

func (m *MockedStatter) DistributionMs(key string, tags stats.Tags, value time.Duration) {
	m.Called(key, tags, value)
}

func (m *MockedStatter) Set(key string, tags stats.Tags, value string) {
	m.Called(key, tags, value)
}

func (m *MockedStatter) WithTags(tags stats.Tags) stats.Client {
	args := m.Called(tags)
	return args.Get(0).(stats.Client)
}

func (m *MockedStatter) ClearTags() stats.Client {
	args := m.Called()
	return args.Get(0).(stats.Client)
}

func (m *MockedStatter) SetPrefix(prefix string) stats.Client {
	args := m.Called(prefix)
	return args.Get(0).(stats.Client)
}
