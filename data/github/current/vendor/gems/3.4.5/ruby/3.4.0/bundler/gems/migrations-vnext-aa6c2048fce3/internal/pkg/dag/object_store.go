package dag

import "context"

// ObjectStore is an interface for storing resource payloads in an object store.
type ObjectStore interface {
	GetPayload(ctx context.Context, namespace, key string) ([]byte, error)
	WritePayload(ctx context.Context, namespace, key string, payload []byte) error
}
