package db

import (
	"context"
	"fmt"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/mocks"
	"github.com/stretchr/testify/assert"
)

func TestShouldRaiseError(t *testing.T) {
	type testCase struct {
		name    string
		err     error
		options *interfaces.QueryOptions
		expect  bool
	}

	randomErr := fmt.Errorf("a random error")

	// Returns a function that can be used to Run the ShouldRaiseError test case
	// This is used to capture the test case variable in the closure.
	assertShouldRaiseError := func(c testCase) func(t *testing.T) {
		return func(t *testing.T) {
			t.Parallel()
			actual := ShouldRaiseError(c.err, c.options)
			if actual != c.expect {
				t.Errorf("ShouldRaiseError returned %t, expected %t", actual, c.expect)
			}
		}
	}

	testCases := []testCase{
		{
			name:    "when error is nil",
			expect:  false,
			err:     nil,
			options: nil,
		},
		{
			name:    "when options is nil",
			err:     randomErr,
			options: nil,
			expect:  true,
		},
		{
			name:    "when options is set and is not a 409 Conflict error",
			err:     randomErr,
			options: &interfaces.QueryOptions{IgnoreExistingDocumentError: true},
			expect:  true,
		},
		{
			name:    "when options is set to false and is a 409 Conflict error",
			err:     mocks.AzureConflictErr,
			options: &interfaces.QueryOptions{IgnoreExistingDocumentError: false},
			expect:  true,
		},
		{
			name:    "returns true when options is set and is a 409 Conflict error",
			err:     mocks.AzureConflictErr,
			options: &interfaces.QueryOptions{IgnoreExistingDocumentError: true},
			expect:  false,
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, assertShouldRaiseError(tc))
	}
}

func TestPatchWithOptionsErrorCases(t *testing.T) {
	t.Parallel()

	logger := &mocks.Logger{}

	t.Run("does not raise error when options are nil", func(t *testing.T) {
		t.Parallel()

		connection := &mocks.CosmosConnection{
			PatchItemFunc: func(ctx context.Context, pk azcosmos.PartitionKey, id string, operations azcosmos.PatchOperations, options *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
				return azcosmos.ItemResponse{}, nil
			},
		}
		database := &Database{connection: connection, tracer: mocks.Tracer{}, statter: mocks.Statter{}}

		item := &models.Item{}

		err := database.PatchWithOptions(
			context.Background(),
			logger,
			item,
			PatchOps{},
			nil,
		)
		if err != nil {
			t.Error("PatchWithOptions should not raise error when options are nil")
		}
	})

	t.Run("does not retry when error is a 404 Not Found", func(t *testing.T) {
		t.Parallel()

		var attempts int
		connection := &mocks.CosmosConnection{
			PatchItemFunc: func(ctx context.Context, pk azcosmos.PartitionKey, id string, operations azcosmos.PatchOperations, options *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
				attempts++
				return azcosmos.ItemResponse{}, mocks.AzureNotFoundErr
			},
		}

		database := &Database{connection: connection, tracer: mocks.Tracer{}, statter: mocks.Statter{}}
		err := database.PatchWithOptions(
			context.Background(),
			logger,
			&models.Item{},
			PatchOps{},
			nil,
		)
		if !Is404NotFound(err) {
			t.Error("PatchWithOptions should return an error when error is a 404 Not Found")
		}
		if attempts != 1 {
			t.Error("PatchWithOptions should not retry when error is a 404 Not Found")
		}
		if err == nil {
			t.Error("PatchWithOptions should return an error when error is a 404 Not Found")
		}
	})

	t.Run("does not retry when error is a 409 Conflict", func(t *testing.T) {
		t.Parallel()

		var attempts int
		connection := &mocks.CosmosConnection{
			PatchItemFunc: func(ctx context.Context, pk azcosmos.PartitionKey, id string, operations azcosmos.PatchOperations, options *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
				attempts++
				return azcosmos.ItemResponse{}, mocks.AzureConflictErr
			},
		}

		database := &Database{connection: connection, tracer: mocks.Tracer{}, statter: mocks.Statter{}}
		err := database.PatchWithOptions(
			context.Background(),
			logger,
			&models.Item{},
			PatchOps{},
			nil,
		)
		if !Is409Conflict(err) {
			t.Error("PatchWithOptions should return an error when error is a 409 Conflict")
		}
		if attempts != 1 {
			t.Error("PatchWithOptions should not retry when error is a 409 Conflict")
		}
		if err == nil {
			t.Error("PatchWithOptions should return an error when error is a 409 Conflict")
		}
	})

	t.Run("retries 3 times by default on retryable errors", func(t *testing.T) {
		t.Parallel()

		var attempts int
		responseErr := mocks.AzureRateLimitErr
		connection := &mocks.CosmosConnection{
			PatchItemFunc: func(ctx context.Context, pk azcosmos.PartitionKey, id string, operations azcosmos.PatchOperations, options *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
				attempts++

				return azcosmos.ItemResponse{}, responseErr
			},
		}

		database := &Database{connection: connection, tracer: mocks.Tracer{}, statter: mocks.Statter{}}
		err := database.PatchWithOptions(
			context.Background(),
			logger,
			&models.Item{},
			PatchOps{},
			nil,
		)
		if err != responseErr {
			t.Fatalf("PatchWithOptions should return the response error but got %+v", err)
		}

		if attempts != 5 {
			t.Error("PatchWithOptions should retry 5 times by default")
		}
	})

	t.Run("does not invoke DB call when context is cancelled", func(t *testing.T) {
		t.Parallel()

		var attempts int
		connection := &mocks.CosmosConnection{
			PatchItemFunc: func(ctx context.Context, pk azcosmos.PartitionKey, id string, operations azcosmos.PatchOperations, options *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
				attempts++
				return azcosmos.ItemResponse{}, mocks.AzureNotFoundErr
			},
		}

		database := &Database{connection: connection, tracer: mocks.Tracer{}, statter: mocks.Statter{}}

		context, cancel := context.WithCancel(context.Background())
		cancel()

		err := database.PatchWithOptions(
			context,
			logger,
			&models.Item{},
			PatchOps{},
			nil,
		)

		assert.Equal(t, 0, attempts)
		assert.Error(t, err)
	})
}

func TestCreateWithOptionsErrorCases(t *testing.T) {
	t.Parallel()

	logger := &mocks.Logger{}

	t.Run("errors on conflict", func(t *testing.T) {
		t.Parallel()

		var attempts int
		connection := &mocks.CosmosConnection{
			CreateItemFunc: func(ctx context.Context, pk azcosmos.PartitionKey, data []byte, options *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
				attempts++
				return azcosmos.ItemResponse{}, mocks.AzureConflictErr
			},
		}

		database := &Database{connection: connection, tracer: mocks.Tracer{}, statter: mocks.Statter{}}

		err := database.CreateWithOptions(
			context.Background(),
			logger,
			&models.Item{},
			nil,
		)

		assert.Equal(t, 1, attempts)
		assert.Error(t, err)
		assert.True(t, Is409Conflict(err))
	})

	t.Run("does not invoke DB call when context is cancelled", func(t *testing.T) {
		t.Parallel()

		var attempts int
		connection := &mocks.CosmosConnection{
			CreateItemFunc: func(ctx context.Context, pk azcosmos.PartitionKey, data []byte, options *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
				attempts++
				return azcosmos.ItemResponse{}, mocks.AzureNotFoundErr
			},
		}

		database := &Database{connection: connection, tracer: mocks.Tracer{}, statter: mocks.Statter{}}

		context, cancel := context.WithCancel(context.Background())
		cancel()

		err := database.CreateWithOptions(
			context,
			logger,
			&models.Item{},
			nil,
		)

		assert.Equal(t, 0, attempts)
		assert.Error(t, err)
	})
}
