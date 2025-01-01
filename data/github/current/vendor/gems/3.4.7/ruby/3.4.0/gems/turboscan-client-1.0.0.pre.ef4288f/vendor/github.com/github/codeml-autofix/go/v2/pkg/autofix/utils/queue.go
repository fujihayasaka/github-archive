package utils

import "container/heap"

// QueueItem must be implemented by types stored in a PriorityQueue.
type QueueItem interface {
	// Priority is the priority of the item.
	Priority() float64
}

// priorityQueue implements heap.Interface and holds QueueItems.
type priorityQueue[T any] struct {
	data     []T
	priority func(T) float64
}

// constantPriorityQueueItem serves only as a building block to ensure that priorityQueue implements heap.Interface.
type constantPriorityQueueItem struct{}

func (item constantPriorityQueueItem) Priority() float64 {
	return 1
}

// Ensure that priorityQueue implements heap.Interface.
var _ heap.Interface = (*priorityQueue[constantPriorityQueueItem])(nil)

func (pq priorityQueue[T]) Len() int { return len(pq.data) }

func (pq priorityQueue[T]) Less(i, j int) bool {
	// We want Pop to give us the highest, not lowest, priority so we use greater than here.
	return pq.priority(pq.data[i]) > pq.priority(pq.data[j])
}

// Push adds an item to the priority queue.
func (pq *priorityQueue[T]) Push(x interface{}) {
	pq.data = append(pq.data, x.(T))
}

// Pop removes the last item from the priority queue.
func (pq *priorityQueue[T]) Pop() interface{} {
	if len(pq.data) == 0 {
		return nil
	}
	n := len(pq.data)
	item := pq.data[n-1]
	// Avoid memory leak, clear the reference to the item.
	pq.data[n-1] = *new(T)
	pq.data = pq.data[:n-1]
	return item
}

func (pq *priorityQueue[T]) Swap(i, j int) {
	(pq.data)[i], (pq.data)[j] = (pq.data)[j], (pq.data)[i]
}

// PriorityQueue is a priority queue that exposes a restricted interface to priorityQueue.
type PriorityQueue[T any] priorityQueue[T]

// DefaultInitialCapacity is the default initial capacity of a priority queue.
// Value of 8 is chosen as a reasonable default to:
// - It's a power of 2, aligning with Go's slice growth pattern
// - avoid waste for small queues
// - minimize reallocations for typical use
const (
	DefaultInitialCapacity = 8
)

// EmptyPriorityQueue creates an empty priority queue.
func EmptyPriorityQueue[T QueueItem]() *PriorityQueue[T] {
	return EmptyPriorityQueueFunc(func(t T) float64 {
		return t.Priority()
	})
}

// EmptyPriorityQueueFunc creates an empty priority queue with a given priority function.
func EmptyPriorityQueueFunc[T any](priority func(T) float64) *PriorityQueue[T] {
	pq := priorityQueue[T]{
		data:     make([]T, 0, DefaultInitialCapacity),
		priority: priority,
	}
	heap.Init(&pq)
	return (*PriorityQueue[T])(&pq)
}

// NewPriorityQueue creates a new priority queue from the given items with O(n) complexity.
func NewPriorityQueue[T QueueItem](items []T) *PriorityQueue[T] {
	return NewPriorityQueueFunc(items, func(t T) float64 {
		return t.Priority()
	})
}

// NewPriorityQueueFunc creates a new priority queue from the given items with O(n) complexity.
// It uses the given priority function.
func NewPriorityQueueFunc[T any](items []T, priority func(T) float64) *PriorityQueue[T] {
	// Use heap.Init instead of heap.Push for O(n) rather than O(n log n) complexity
	pq := priorityQueue[T]{
		data:     make([]T, len(items)),
		priority: priority,
	}
	copy(pq.data, items)
	heap.Init(&pq)
	return (*PriorityQueue[T])(&pq)
}

// Push adds an item to the priority queue.
func (pq *PriorityQueue[T]) Push(item T) {
	if pq == nil {
		panic("priority queue is nil")
	}
	heap.Push((*priorityQueue[T])(pq), item)
}

// Pop removes the item with the highest priority from the priority queue.
func (pq *PriorityQueue[T]) Pop() T {
	return heap.Pop((*priorityQueue[T])(pq)).(T)
}

// Len returns the number of items in the priority queue.
func (pq *PriorityQueue[T]) Len() int {
	return len(pq.data)
}

// IsEmpty returns true if the priority queue is empty.
func (pq *PriorityQueue[T]) IsEmpty() bool {
	return pq.Len() == 0
}
