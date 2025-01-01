package dag

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/kafka"
	"github.com/github/migrations-vnext/internal/pkg/set"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"golang.org/x/sync/errgroup"
	"google.golang.org/protobuf/proto"
)

// Worker is a DAG worker that processes eligible nodes.
type Worker struct {
	concurrencyLimit int
	dag              DAG
	eventProducer    kafka.Producer
	logger           log.Logger
	objectStore      ObjectStore
	processing       set.Set[ID]
	processingMu     sync.Mutex
	resourceProducer kafka.Producer
}

// NewWorker creates a new DAG worker.
func NewWorker(
	concurrencyLimit int,
	dag DAG,
	objectStore ObjectStore,
	eventProducer kafka.Producer,
	resourceProducer kafka.Producer,
	logger log.Logger,
) *Worker {
	return &Worker{
		concurrencyLimit: concurrencyLimit,
		dag:              dag,
		eventProducer:    eventProducer,
		logger:           logger,
		objectStore:      objectStore,
		processing:       set.New[ID](),
		processingMu:     sync.Mutex{},
		resourceProducer: resourceProducer,
	}
}

// maxKafkaSize is the cutoff for payloads to be written to Kafka.
// If the payload size is greater than this, it will be written to the object store.
const maxKafkaSize = 4 * 1024 * 1024

// handleEventNode handles nodes of kind EventNode.
func (w *Worker) handleEventNode(ctx context.Context, namespace string, node Node) error {
	// Sanity check
	if node.Kind != EventNode {
		return fmt.Errorf("EventNode handler received invalid kind, got: %s", node.Kind.String())
	}

	// Get the payload
	payload, err := w.objectStore.GetPayload(ctx, namespace, string(node.ID))
	if err != nil {
		return fmt.Errorf("failed to get event payload: %w", err)
	}
	w.logger.Debug("got payload", kvp.String("node", string(node.ID)))

	// Write the event to Kafka.
	if err := w.eventProducer.Produce(ctx, payload); err != nil {
		return fmt.Errorf("failed to produce event %s: %w", node.ID, err)
	}

	return nil
}

// handleResourceNode handles nodes of kind ResourceNode.
func (w *Worker) handleResourceNode(ctx context.Context, namespace string, node Node) error {
	// Sanity check
	if node.Kind != ResourceNode {
		return fmt.Errorf("ResourceNode handler received invalid kind, got: %s", node.Kind.String())
	}

	// Get the payload
	payload, err := w.objectStore.GetPayload(ctx, namespace, string(node.ID))
	if err != nil {
		return fmt.Errorf("failed to get payload: %w", err)
	}
	w.logger.Debug("got payload", kvp.String("node", string(node.ID)))

	// if payload is too large, we write to kafka a resource that points to object store
	if len(payload) > maxKafkaSize {
		p, err := w.buildObjectStoreResource(string(node.ID), len(payload))
		if err != nil {
			return fmt.Errorf("failed to build object store resource: %w", err)
		}
		payload = p
	}

	// Write the payload to Kafka
	if err = w.resourceProducer.Produce(ctx, payload); err != nil {
		return fmt.Errorf("failed to produce payload: %w", err)
	}

	return nil
}

// ProcessEligibleNodes runs the DAG worker to process eligible nodes
func (w *Worker) ProcessEligibleNodes(ctx context.Context, namespace string) error {
	// Process eligible nodes
	for ; ctx.Err() == nil; time.Sleep(100 * time.Millisecond) {
		nodes, err := w.dag.EligibleNodes(ctx, namespace)
		if err != nil {
			return fmt.Errorf("failed to get eligible nodes: %w", err)
		}

		// Find nodes that are not in the in-processing set.
		// Skip nodes that are not resource nodes until we introduce event handling.
		var eligibleNodes []Node
		for _, node := range nodes {
			if w.isInProcessing(node.ID) {
				continue
			}
			eligibleNodes = append(eligibleNodes, node)
		}
		if len(eligibleNodes) == 0 {
			continue
		}
		w.logger.Info("found eligible nodes", kvp.Any("nodes", eligibleNodes))

		var errGrp errgroup.Group
		errGrp.SetLimit(w.concurrencyLimit)
		for _, node := range eligibleNodes {
			errGrp.Go(func() error {
				var err error
				switch node.Kind {
				case EventNode:
					err = w.handleEventNode(ctx, namespace, node)
				case ResourceNode:
					err = w.handleResourceNode(ctx, namespace, node)
				default:
					err = fmt.Errorf("unsupported node kind: %s, skipping", node.Kind)
				}
				if err != nil {
					return err
				}

				// Add node to the in-processing set
				w.addToProcessing(node.ID)
				return nil
			})
		}
		if err := errGrp.Wait(); err != nil {
			return fmt.Errorf("failed to process eligible nodes: %w", err)
		}
	}
	return nil
}

// isInProcessing checks if a node is in the in-processing set.
func (w *Worker) isInProcessing(node ID) bool {
	w.processingMu.Lock()
	defer w.processingMu.Unlock()
	_, ok := w.processing[node]
	return ok
}

// addToProcessing adds a node to the in-processing set.
func (w *Worker) addToProcessing(node ID) {
	w.processingMu.Lock()
	defer w.processingMu.Unlock()
	w.processing.Add(node)
}

// buildObjectStoreResource builds a resource that points to an object store.
func (w *Worker) buildObjectStoreResource(id string, size int) ([]byte, error) {
	w.logger.Info("payload too large, writing to object store",
		kvp.String("node", id), kvp.Int("size", size))

	r := v1.Resource{
		Location: v1.ResourceLocationType_RESOURCE_LOCATION_TYPE_OBJECT_STORE,
		ObjectStore: &v1.ResourceLocationObjectStore{
			Key:  id,
			Size: int64(size),
		},
	}
	payload, err := proto.Marshal(&r)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal resource: %w", err)
	}
	return payload, nil
}
