package cosmoslocker

import (
	"context"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func Test_Lock(t *testing.T) {
	tests := []struct {
		name         string
		lockId       string
		lockExists   bool
		lockExpired  bool
		obtainedLock bool
	}{
		{
			name:         "Lock is obtained when lock does not exist",
			lockId:       "test-lock",
			lockExists:   false,
			obtainedLock: true,
		},
		{
			name:         "Lock is not obtained when lock exists AND is not expired",
			lockId:       "test-lock",
			lockExists:   true,
			lockExpired:  false,
			obtainedLock: false,
		},
		{
			name:         "Lock is obtained when lock exists BUT is expired",
			lockId:       "test-lock",
			lockExists:   true,
			lockExpired:  true,
			obtainedLock: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pegomock.RegisterMockTestingT(t)
			c, telem, statter, logger, mockDb := helpers.SetupMocks(t)
			ctx := context.Background()

			pegomock.When(mockDb.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(mockDb.GetConnection()).ThenReturn(c)
			pegomock.When(mockDb.GetGatewayConnection()).ThenReturn(c)
			pegomock.When(mockDb.GetStatter()).ThenReturn(statter)

			locker := NewCosmosLocker(mockDb, logger, 30*time.Minute, nil)

			k := &models.Key{
				PartitionKey: "locks",
				Id:           tt.lockId,
			}

			timeStamp := time.Now()

			createIfNotExistsMock := pegomock.When(
				mockDb.CreateIfNotExists(ctx, logger, k),
			).ThenReturn(true, nil)

			if tt.lockExists {
				createIfNotExistsMock = pegomock.When(
					mockDb.CreateIfNotExists(ctx, logger, k),
				).ThenReturn(false, nil)
			}

			if tt.lockExpired {
				timeStamp = timeStamp.Add(-1 * time.Hour)
				createIfNotExistsMock.ThenReturn(true, nil)
			}

			if tt.lockExists {
				pegomock.When(
					c.ReadItem(
						pegomock.Any[context.Context](),
						pegomock.Eq(azcosmos.NewPartitionKeyString("locks")),
						pegomock.Eq(tt.lockId),
						pegomock.Any[*azcosmos.ItemOptions](),
					),
				).ThenReturn(
					helpers.MockAzureItemResponse(t, &cosmosLock{
						Key:       k,
						Timestamp: timeStamp.Unix(),
					}),
					nil,
				)
			} else {
				pegomock.When(
					c.ReadItem(
						pegomock.Any[context.Context](),
						pegomock.Eq(azcosmos.NewPartitionKeyString("locks")),
						pegomock.Eq(tt.lockId),
						pegomock.Any[*azcosmos.ItemOptions](),
					),
				).ThenReturn(
					helpers.MockAzureItemResponseWith404(t),
					nil,
				)
			}

			lock, err := locker.Lock(ctx, tt.lockId)

			if tt.obtainedLock {
				assert.NotNil(t, lock)
				assert.Nil(t, err)
				if tt.lockExpired {
					mockDb.VerifyWasCalledOnce().DeleteWithOptions(ctx, logger, k, nil)
				}
			} else {
				assert.Nil(t, lock)
				assert.NotNil(t, err)
			}
		})
	}
}

func Test_Unlock(t *testing.T) {
	tests := []struct {
		name             string
		lockId           string
		deleteSuccessful bool
	}{
		{
			name:             "Unlock returns nil when unlock is successful",
			lockId:           "test-lock",
			deleteSuccessful: true,
		},
		{
			name:   "Unlock returns an error when unlock is unsuccessful",
			lockId: "test-lock",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, _, _, logger, mockDb := helpers.SetupMocks(t)
			ctx := context.Background()

			k := &models.Key{
				PartitionKey: "locks",
				Id:           tt.lockId,
			}

			if tt.deleteSuccessful {
				pegomock.When(
					mockDb.DeleteWithOptions(
						pegomock.Any[context.Context](),
						pegomock.Eq(logger),
						pegomock.Eq(k),
						pegomock.Any[*interfaces.QueryOptions](),
					),
				).ThenReturn(nil)
			} else {
				pegomock.When(
					mockDb.DeleteWithOptions(
						pegomock.Any[context.Context](),
						pegomock.Eq(logger),
						pegomock.Eq(k),
						pegomock.Any[*interfaces.QueryOptions](),
					),
				).ThenReturn(assert.AnError)
			}

			lock := &cronLock{
				id:     tt.lockId,
				db:     mockDb,
				logger: logger,
			}

			err := lock.Unlock(ctx)

			if tt.deleteSuccessful {
				assert.Nil(t, err)
			} else {
				assert.NotNil(t, err)
			}
		})
	}
}
