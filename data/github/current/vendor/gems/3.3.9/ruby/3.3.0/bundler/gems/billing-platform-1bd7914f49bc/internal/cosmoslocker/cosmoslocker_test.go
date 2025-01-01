package cosmoslocker

import (
	"context"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func Test_Lock(t *testing.T) {
	tests := []struct {
		name                          string
		lockId                        string
		lockExists                    bool
		lockExpired                   bool
		bpExpireOldCosmosLocksEnabled bool
	}{
		{
			name:   "Lock is obtained when no lock does not exist",
			lockId: "test-lock",
		},
		{
			name:       "Lock is not obtained when the lock exists",
			lockId:     "test-lock",
			lockExists: true,
		},
		{
			name:        "Lock is not obtained when bp_expire_old_cosmos_locks ff is not enabled and lock is expired",
			lockId:      "test-lock",
			lockExists:  true,
			lockExpired: true,
		},
		{
			name:                          "Lock is not obtained when bp_expire_old_cosmos_locks ff is enabled and lock is not expired",
			lockId:                        "test-lock",
			lockExists:                    true,
			bpExpireOldCosmosLocksEnabled: true,
		},
		{
			name:                          "Lock is obtained when bp_expire_old_cosmos_locks ff is enabled and lock is expired",
			lockId:                        "test-lock",
			lockExists:                    true,
			lockExpired:                   true,
			bpExpireOldCosmosLocksEnabled: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mocker := pegomock.WithT(t)
			pegomock.RegisterMockTestingT(t)
			c, telem, statter, logger, mockDb := helpers.SetupMocks(t)
			ctx := context.Background()

			pegomock.When(mockDb.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(mockDb.GetConnection()).ThenReturn(c)
			pegomock.When(mockDb.GetGatewayConnection()).ThenReturn(c)
			pegomock.When(mockDb.GetStatter()).ThenReturn(statter)

			mockFlagChecker := fakes.NewMockFlagChecker(mocker)

			locker := NewCosmosLocker(mockDb, logger, 30*time.Minute, mockFlagChecker)

			k := &models.Key{
				PartitionKey: "locks",
				Id:           tt.lockId,
			}

			createIfNotExistsMock := pegomock.When(
				mockDb.CreateIfNotExists(ctx, logger, k),
			).ThenReturn(true, nil)

			if tt.lockExists {
				createIfNotExistsMock = pegomock.When(
					mockDb.CreateIfNotExists(ctx, logger, k),
				).ThenReturn(false, nil)
			}

			if !tt.bpExpireOldCosmosLocksEnabled {
				pegomock.When(
					mockFlagChecker.CheckGlobalFeature(
						ctx,
						"bp_expire_old_cosmos_locks",
					),
				).ThenReturn(false, nil)

				lock, err := locker.Lock(ctx, tt.lockId)

				if tt.lockExists {
					assert.Nil(t, lock)
					assert.NotNil(t, err)
				} else {
					assert.NotNil(t, lock)
					assert.Nil(t, err)
				}

				return
			}

			pegomock.When(
				mockFlagChecker.CheckGlobalFeature(
					ctx,
					"bp_expire_old_cosmos_locks",
				),
			).ThenReturn(true, nil)

			timeStamp := time.Now()

			if tt.lockExpired {
				timeStamp = timeStamp.Add(-1 * time.Hour)
				createIfNotExistsMock.ThenReturn(true, nil)
			}

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

			lock, err := locker.Lock(ctx, tt.lockId)

			if tt.lockExpired {
				mockDb.VerifyWasCalledOnce().DeleteWithOptions(ctx, logger, k, nil)
				assert.NotNil(t, lock)
				assert.Nil(t, err)
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
