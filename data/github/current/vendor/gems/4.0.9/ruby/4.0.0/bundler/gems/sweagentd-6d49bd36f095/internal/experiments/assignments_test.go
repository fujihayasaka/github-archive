package experiments

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/assert"
)

func TestNewVSCodeAssignments(t *testing.T) {
	tests := []struct {
		name     string
		response *CopilotExpAssignmentResponse
		expected *Assignments
	}{
		{
			name: "basic features",
			response: &CopilotExpAssignmentResponse{
				AssignmentContext: "test-context",
				Configs: []ConfigEntry{
					{
						ID: "vscode",
						Parameters: map[string]any{
							"feature1": true,
							"feature2": "value2",
						},
					},
				},
			},
			expected: &Assignments{
				Features: map[string]any{
					"feature1": true,
					"feature2": "value2",
				},
				AssignmentContext: "test-context",
			},
		},
		{
			name: "multiple configs",
			response: &CopilotExpAssignmentResponse{
				AssignmentContext: "test-context",
				Configs: []ConfigEntry{
					{
						ID: "vscode",
						Parameters: map[string]any{
							"feature1": true,
							"feature2": "value2",
						},
					},
					{
						ID: "otherID",
						Parameters: map[string]any{
							"feature3": "value3",
						},
					},
				},
			},
			expected: &Assignments{
				Features: map[string]any{
					"feature1": true,
					"feature2": "value2",
				},
				AssignmentContext: "test-context",
			},
		},
		{
			name: "no vscode config",
			response: &CopilotExpAssignmentResponse{
				AssignmentContext: "test-context",
				Configs: []ConfigEntry{
					{
						ID: "otherID",
						Parameters: map[string]any{
							"feature1": true,
						},
					},
				},
			},
			expected: &Assignments{
				Features:          map[string]any{},
				AssignmentContext: "test-context",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assignments := NewVSCodeAssignments(tt.response)
			assert.Equal(t, tt.response.AssignmentContext, assignments.AssignmentContext)
			assert.Equal(t, tt.expected.Features, assignments.Features)
			assert.NotZero(t, assignments.lastUpdate)
		})
	}
}

func TestAssignmentsGetVariation(t *testing.T) {
	tests := []struct {
		name               string
		assignments        *Assignments
		featureName        string
		expectedAssignment *Assignment
		expectedFound      bool
	}{
		{
			name: "existing feature",
			assignments: &Assignments{
				Features: map[string]any{
					"feature1": "value1",
				},
				AssignmentContext: "test-context",
			},
			featureName: "feature1",
			expectedAssignment: &Assignment{
				Variation: "value1",
				Context:   "test-context",
			},
			expectedFound: true,
		},
		{
			name: "non-existing feature",
			assignments: &Assignments{
				Features:          map[string]any{},
				AssignmentContext: "test-context",
			},
			featureName:        "feature2",
			expectedAssignment: nil,
			expectedFound:      false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assignment, found := tt.assignments.GetVariation(tt.featureName)
			assert.Equal(t, tt.expectedFound, found)
			if found {
				assert.Equal(t, tt.expectedAssignment.Variation, assignment.Variation)
				assert.Equal(t, tt.expectedAssignment.Context, assignment.Context)
			}
		})
	}
}

var testCacheConfig = CacheConfig{
	TTL:             5 * time.Minute,
	MaxSize:         1000,
	CleanupInterval: 1 * time.Minute,
}

func TestAssignmentsExpired(t *testing.T) {
	assignments := &Assignments{
		lastUpdate: time.Now().Add(-time.Hour),
	}
	assert.True(t, assignments.expired(testCacheConfig.TTL))
}

func TestAssignmentsCache(t *testing.T) {
	cache := newAssignmentsCacheWithWorker(context.Background(), observability.NewNoopExporters(), testCacheConfig, false)

	// Test basic get/set
	key1 := CacheKey{RandomizationUnit: "unit1", TrafficFilters: "filters1"}
	assignment1 := &Assignments{
		Features:          map[string]any{"feature1": "value1"},
		AssignmentContext: "context1",
		lastUpdate:        time.Now(),
	}

	// Initially empty
	assignements := cache.Get(key1)
	assert.Nil(t, assignements)

	// Set and get
	cache.Set(key1, assignment1)
	retrievedAssignments := cache.Get(key1)
	assert.Equal(t, assignment1.Features, retrievedAssignments.Features)
	assert.Equal(t, assignment1.AssignmentContext, retrievedAssignments.AssignmentContext)
}

func TestAssignmentsCacheExpiration(t *testing.T) {
	cache := newAssignmentsCacheWithWorker(context.Background(), observability.NewNoopExporters(), testCacheConfig, false)

	key1 := CacheKey{RandomizationUnit: "unit1", TrafficFilters: "filters1"}
	expiredAssignment := &Assignments{
		Features:          map[string]any{"feature1": "value1"},
		AssignmentContext: "context1",
		lastUpdate:        time.Now().Add(-testCacheConfig.TTL - time.Minute),
	}

	cache.Set(key1, expiredAssignment)

	// Should not retrieve expired assignment
	assignments := cache.Get(key1)
	assert.Nil(t, assignments)
}

func TestAssignmentsCacheMultipleEntries(t *testing.T) {
	cache := newAssignmentsCacheWithWorker(context.Background(), observability.NewNoopExporters(), testCacheConfig, false)

	key1 := CacheKey{RandomizationUnit: "unit1", TrafficFilters: "filters1"}
	key2 := CacheKey{RandomizationUnit: "unit2", TrafficFilters: "filters2"}

	assignment1 := &Assignments{
		Features:          map[string]any{"feature1": "value1"},
		AssignmentContext: "context1",
		lastUpdate:        time.Now(),
	}

	assignment2 := &Assignments{
		Features:          map[string]any{"feature2": "value2"},
		AssignmentContext: "context2",
		lastUpdate:        time.Now(),
	}

	cache.Set(key1, assignment1)
	cache.Set(key2, assignment2)

	// Both should be retrievable
	retrieved1 := cache.Get(key1)
	retrieved2 := cache.Get(key2)

	assert.Equal(t, assignment1.Features, retrieved1.Features)
	assert.Equal(t, assignment2.Features, retrieved2.Features)
}

func TestAssignmentsCacheCleanupExpired(t *testing.T) {
	cache := newAssignmentsCacheWithWorker(t.Context(), observability.NewNoopExporters(), testCacheConfig, false)

	key1 := CacheKey{RandomizationUnit: "unit1", TrafficFilters: "filters1"}
	key2 := CacheKey{RandomizationUnit: "unit2", TrafficFilters: "filters2"}

	validAssignment := &Assignments{
		Features:          map[string]any{"feature1": "value1"},
		AssignmentContext: "context1",
		lastUpdate:        time.Now(),
	}

	expiredAssignment := &Assignments{
		Features:          map[string]any{"feature2": "value2"},
		AssignmentContext: "context2",
		lastUpdate:        time.Now().Add(-testCacheConfig.TTL - time.Minute),
	}

	cache.Set(key1, validAssignment)
	cache.Set(key2, expiredAssignment)

	// Before cleanup, expired entry exists in the map but Get returns false
	assert.Len(t, cache.entries, 2)
	assignment2 := cache.Get(key2)
	assert.Nil(t, assignment2)
	// Get cleans cache: expired entry is removed from the map
	assert.Len(t, cache.entries, 1)

	// Valid entry should still be accessible
	assignment1 := cache.Get(key1)
	assert.NotNil(t, assignment1)
}

func TestAssignmentsCacheSizeReduction(t *testing.T) {
	cache := newAssignmentsCacheWithWorker(context.Background(), observability.NewNoopExporters(), testCacheConfig, false)

	// First, add exactly testCacheConfig.MaxSize entries (shouldn't trigger reduction)
	baseTime := time.Now()
	for i := 0; i < testCacheConfig.MaxSize+1; i++ {
		assignment := &Assignments{
			Features:          map[string]any{"feature": "value"},
			AssignmentContext: "context",
			lastUpdate:        baseTime.Add(time.Duration(i) * time.Second),
		}
		cache.Set(CacheKey{RandomizationUnit: fmt.Sprintf("entry-%d", i), TrafficFilters: "filters"}, assignment)
	}

	// Trigger reduction
	cache.reduceCacheSize()

	// Should now be reduced to 80% of testCacheConfig.MaxSize
	targetSize := int(float64(testCacheConfig.MaxSize) * 0.8)
	cache.mu.RLock()
	actualSize := len(cache.entries)
	cache.mu.RUnlock()

	assert.Equal(t, targetSize, actualSize, "Cache should be reduced to 80% of max size after exceeding limit")

	// Verify that the newest entry is still there (the one that triggered the reduction)
	cache.mu.RLock()
	newestKey := CacheKey{RandomizationUnit: fmt.Sprintf("entry-%d", testCacheConfig.MaxSize), TrafficFilters: "filters"}
	_, exists := cache.entries[newestKey]
	assert.True(t, exists, "The newest entry that triggered reduction should still exist")
	cache.mu.RUnlock()
}

func TestGenerateCacheKey(t *testing.T) {
	tests := []struct {
		name              string
		randomizationUnit *TrafficFilter
		trafficFilters    TrafficFilters
		expected          CacheKey
	}{
		{
			name:              "nil randomization unit and empty traffic filters",
			randomizationUnit: nil,
			trafficFilters:    TrafficFilters{},
			expected: CacheKey{
				RandomizationUnit: "",
				TrafficFilters:    "",
			},
		},
		{
			name: "with randomization unit only",
			randomizationUnit: &TrafficFilter{
				Header: VSCodeExtensionNameHeader,
				Value:  "test-extension",
			},
			trafficFilters: TrafficFilters{},
			expected: CacheKey{
				RandomizationUnit: "X-VSCode-ExtensionName:test-extension",
				TrafficFilters:    "",
			},
		},
		{
			name:              "with traffic filters only",
			randomizationUnit: nil,
			trafficFilters: TrafficFilters{
				{
					Header: CopilotRepositoryHeader,
					Value:  "test-repo",
				},
			},
			expected: CacheKey{
				RandomizationUnit: "",
				TrafficFilters:    "[X-Copilot-Repository:test-repo]",
			},
		},
		{
			name: "with both randomization unit and traffic filters",
			randomizationUnit: &TrafficFilter{
				Header: VSCodeExtensionNameHeader,
				Value:  "test-extension",
			},
			trafficFilters: TrafficFilters{
				{
					Header: CopilotRepositoryHeader,
					Value:  "test-repo",
				},
				{
					Header: CopilotOrgsHeader,
					Value:  "test-org",
				},
			},
			expected: CacheKey{
				RandomizationUnit: "X-VSCode-ExtensionName:test-extension",
				TrafficFilters:    "[X-Copilot-Orgs:test-org X-Copilot-Repository:test-repo]",
			},
		},
		{
			name: "traffic filters are sorted consistently",
			randomizationUnit: &TrafficFilter{
				Header: VSCodeExtensionNameHeader,
				Value:  "test-extension",
			},
			trafficFilters: TrafficFilters{
				// Deliberately putting these in reverse alphabetical order
				{
					Header: CopilotOrgsHeader,
					Value:  "test-org",
				},
				{
					Header: CopilotRepositoryHeader,
					Value:  "test-repo",
				},
			},
			expected: CacheKey{
				RandomizationUnit: "X-VSCode-ExtensionName:test-extension",
				// Should be sorted alphabetically by the full "Header:Value" string
				TrafficFilters: "[X-Copilot-Orgs:test-org X-Copilot-Repository:test-repo]",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := GenerateCacheKey(tt.randomizationUnit, tt.trafficFilters)
			assert.Equal(t, tt.expected, result)
		})
	}
}
