package dag

import (
	"context"
	"sync"

	"github.com/github/migrations-vnext/internal/pkg/set"
)

// Enforce interface implementation
var _ DAG = &MemoryDAG{}

// MemoryDAG in an in-memory implementation of the DAG interface.
// This implementation should only be used for development and
// testing.
type MemoryDAG struct {
	eligibleNodes         set.Set[Node]
	nodeIDsToDependencies map[ID]set.Set[ID]
	nodeIDsToDependents   map[ID]set.Set[ID]
	nodeIDsToNodes        map[ID]Node
	mu                    sync.Mutex
	processedNodes        map[ID]struct{}
}

// NewMemoryDAG creates and returns a MemoryDAG.
func NewMemoryDAG() *MemoryDAG {
	return &MemoryDAG{
		eligibleNodes:         set.New[Node](),
		nodeIDsToDependencies: make(map[ID]set.Set[ID]),
		nodeIDsToDependents:   make(map[ID]set.Set[ID]),
		nodeIDsToNodes:        make(map[ID]Node),
		mu:                    sync.Mutex{},
		processedNodes:        make(map[ID]struct{}),
	}
}

// AddNode implements the AddNode method of the DAG interface.
func (m *MemoryDAG) AddNode(_ context.Context, _ string, kind NodeKind, id ID, dependencies ...Node) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Add node to global node list
	m.nodeIDsToNodes[id] = Node{ID: id, Kind: kind}

	for _, dependency := range dependencies {
		// Record this node as a dependent of the dependencies
		if _, ok := m.nodeIDsToDependents[dependency.ID]; !ok {
			m.nodeIDsToDependents[dependency.ID] = set.New[ID]()
		}
		m.nodeIDsToDependents[dependency.ID].Add(id)

		// Record dependencies of this node
		if _, ok := m.nodeIDsToDependencies[id]; !ok {
			m.nodeIDsToDependencies[id] = set.New[ID]()
		}
		m.nodeIDsToDependencies[id].Add(dependency.ID)
	}

	// Mark as eligible if the node has no dependencies
	if len(m.nodeIDsToDependencies[id]) == 0 {
		m.eligibleNodes.Add(m.nodeIDsToNodes[id])
	}

	return nil
}

// EligibleNodes implements the EligibleNodes method of the DAG interface.
func (m *MemoryDAG) EligibleNodes(_ context.Context, _ string) ([]Node, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	return m.eligibleNodes.ToSlice(), nil
}

// MarkAsProcessed implements the MarkAsProcessed method of the DAG interface.
//
// At the moment, only ResourceNodes are supported.
func (m *MemoryDAG) MarkAsProcessed(_ context.Context, _ string, nodes []Node) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, node := range nodes {
		// Record node as processed
		m.processedNodes[node.ID] = struct{}{}
		m.eligibleNodes.Remove(node)

		// Unlink dependencies that dependent nodes have on the current node.
		// Check if the current node being processed results in a new eligible node.
		// If so, add it to the eligible nodes list.
		for dependentID := range m.nodeIDsToDependents[node.ID] {
			m.nodeIDsToDependencies[dependentID].Remove(node.ID)
			if len(m.nodeIDsToDependencies[dependentID]) == 0 {
				m.eligibleNodes.Add(m.nodeIDsToNodes[dependentID])
			}
		}
	}

	return nil
}
