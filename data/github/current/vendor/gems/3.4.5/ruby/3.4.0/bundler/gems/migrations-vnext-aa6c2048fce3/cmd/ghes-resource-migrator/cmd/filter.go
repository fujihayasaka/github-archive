package cmd

import (
	"crypto/sha256"
	"fmt"
	"os"
	"sync"

	"github.com/bits-and-blooms/bloom/v3"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"google.golang.org/protobuf/proto"
)

type (
	// resourceFilter is a struct that contains a bloom filter and a mutex to protect access to the filter.
	// This filter is used to prevent duplicate resources from being sent to the migration target.
	resourceFilter struct {
		mutex      sync.Mutex
		filter     *bloom.BloomFilter
		filterPath string
	}

	filter interface {
		contains(*v1.Resource) (bool, error)
		add(*v1.Resource) error
		save() error
	}

	// noopFilter is a struct that implements the filter interface but does nothing.
	noopFilter struct{}
)

const (
	bloomFilterElements       = 1_000_000
	bloomFilterFalsePositives = 0.01
)

// make sure noopFilter implements the filter interface.
var _ filter = &noopFilter{}

func newResourceFilter(path string) (*resourceFilter, error) {
	// check if the file exists
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return &resourceFilter{
			filter:     bloom.NewWithEstimates(bloomFilterElements, bloomFilterFalsePositives),
			filterPath: path,
		}, nil
	}

	// load the bloom filter from the file
	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("error opening bloom filter file: %w", err)
	}
	defer func() { _ = file.Close() }()

	var g bloom.BloomFilter
	_, err = g.ReadFrom(file)
	if err != nil {
		return nil, fmt.Errorf("error reading bloom filter file: %w", err)
	}

	return &resourceFilter{
		filter:     &g,
		filterPath: path,
	}, nil
}

// save saves the bloom filter to the configured path.
func (r *resourceFilter) save() error {
	if r.filterPath == "" {
		return nil
	}

	file, err := os.Create(r.filterPath)
	if err != nil {
		return fmt.Errorf("error creating bloom filter file: %w", err)
	}
	defer func() { _ = file.Close() }()

	r.mutex.Lock()
	defer r.mutex.Unlock()
	_, err = r.filter.WriteTo(file)
	if err != nil {
		return fmt.Errorf("error writing bloom filter file: %w", err)
	}

	return nil
}

// contains tells us if a given resource exists in the filter.
func (r *resourceFilter) contains(resource *v1.Resource) (bool, error) {
	// enforce deterministic serialization
	data, err := proto.MarshalOptions{Deterministic: true}.Marshal(resource)
	if err != nil {
		return false, fmt.Errorf("error marshaling resource: %w", err)
	}

	// hash the serialized data
	h := sha256.Sum256(data)

	// check if the hash is in the bloom filter
	r.mutex.Lock()
	defer r.mutex.Unlock()
	return r.filter.Test(h[:]), nil
}

// updateFilter updates the bloom filter with the given resource by adding its hash to the filter.
func (r *resourceFilter) add(resource *v1.Resource) error {
	// enforce deterministic serialization
	data, err := proto.MarshalOptions{Deterministic: true}.Marshal(resource)
	if err != nil {
		return fmt.Errorf("error marshaling resource: %w", err)
	}

	// hash the serialized data
	h := sha256.Sum256(data)

	r.mutex.Lock()
	r.filter.Add(h[:])
	r.mutex.Unlock()

	return nil
}

func (n noopFilter) contains(_ *v1.Resource) (bool, error) {
	return false, nil
}

func (n noopFilter) add(_ *v1.Resource) error {
	return nil
}

func (n noopFilter) save() error { return nil }

// createFilter creates a new filter based on the given path, if the path is empty
// it returns a noop filter.
func createFilter(path string) (filter, error) {
	if path == "" {
		return noopFilter{}, nil
	}

	return newResourceFilter(path)
}
