package dag

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/migrationctx"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"google.golang.org/protobuf/proto"
)

// Enforce interface implementation
var _ Manager = &managerImpl{}

// Manager is an interface which defines functionality for managing
// the DAG. It accepts domain-level objects (e.g. v1.Resource).
type Manager interface {
	AddEvent(ctx context.Context, event *v1.Event) error
	AddResource(ctx context.Context, resource *v1.Resource) error
}

type managerImpl struct {
	dag         DAG
	logger      log.Logger
	objectStore ObjectStore
}

// NewManager returns a Manager who will use the provided DAG and object
// store for node management.
func NewManager(dag DAG, objectStore ObjectStore, logger log.Logger) Manager {
	return &managerImpl{
		dag:         dag,
		logger:      logger.WithFields(kvp.String("component", "manager")),
		objectStore: objectStore,
	}
}

// AddEvent takes an Event and stores it within the DAG and object store.
func (m managerImpl) AddEvent(ctx context.Context, event *v1.Event) error {
	ns, err := migrationctx.Namespace(event)
	if err != nil {
		return fmt.Errorf("error getting namespace: %w", err)
	}

	dependencies, err := prepareEventDeps(event)
	if err != nil {
		return fmt.Errorf("error preparing event deps for insertion into dag: %w", err)
	}

	// Store the payload in the object store
	e, err := proto.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal event for writing: %w", err)
	}

	if err = m.objectStore.WritePayload(ctx, ns, event.EventId, e); err != nil {
		return fmt.Errorf("failed to store event payload: %w", err)
	}

	// Create dependency slice
	deps := []Node{{ID: ID(event.GetResourceId()), Kind: ResourceNode}}
	for _, dependency := range dependencies.ToSlice() {
		deps = append(deps, Node{ID: dependency, Kind: ResourceNode})
	}
	// Add event to DAG along with dependencies
	if err := m.dag.AddNode(ctx, ns, EventNode, ID(event.EventId), deps...); err != nil {
		m.logger.WithError(err).Warn("failed to add node to DAG")
		return fmt.Errorf("error adding node to DAG: %w", err)
	}

	return nil
}

// AddResource takes a Resource and stores it within the DAG and object store
// (if required). If either operation fails an error is returned.
func (m managerImpl) AddResource(ctx context.Context, resource *v1.Resource) error {
	ns, err := migrationctx.Namespace(resource)
	if err != nil {
		return fmt.Errorf("error getting namespace: %w", err)
	}

	nodes, err := prepareResource(resource)
	if err != nil {
		return fmt.Errorf("error preparing resource for insertion into dag: %w", err)
	}

	for _, node := range nodes {
		if node.Payload != nil {
			// Store the payload in the object store
			b, err := proto.Marshal(node.Payload)
			if err != nil {
				return fmt.Errorf("failed to marshal resource for writing: %w", err)
			}

			err = m.objectStore.WritePayload(ctx, ns, string(node.ID), b)
			if err != nil {
				return fmt.Errorf("failed to store payload: %w", err)
			}
		}

		var deps []Node
		for _, dependency := range node.Deps.ToSlice() {
			deps = append(deps, Node{ID: dependency, Kind: ResourceNode})
		}

		if err = m.dag.AddNode(ctx, ns, ResourceNode, node.ID, deps...); err != nil {
			return fmt.Errorf("error adding node to DAG: %w", err)
		}
	}

	return nil
}
