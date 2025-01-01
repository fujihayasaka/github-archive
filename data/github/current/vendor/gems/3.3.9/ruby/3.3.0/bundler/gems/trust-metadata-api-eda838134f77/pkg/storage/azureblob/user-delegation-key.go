package azureblob

import (
	"context"
	"sync"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/sas"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/service"
)

type UserDelegationKeyRefresher struct {
	client *service.Client
	udc    *service.UserDelegationCredential
	m      sync.RWMutex
}

func newUserDelegationKeyRefresher(client *service.Client) (*UserDelegationKeyRefresher, error) {
	userDelegationKeyRefresher := &UserDelegationKeyRefresher{
		client: client,
	}

	// fetch the first key
	udc, err := userDelegationKeyRefresher.fetchUserDelegationKey(context.Background())
	if err != nil {
		return nil, err
	}
	userDelegationKeyRefresher.setUserDelegationKey(udc)

	// schedule for a continuous refresh in background
	userDelegationKeyRefresher.refreshUserDelegationKey(context.Background())

	return userDelegationKeyRefresher, nil
}

func (u *UserDelegationKeyRefresher) GetUserDelegationKey() *service.UserDelegationCredential {
	u.m.RLock()
	defer u.m.RUnlock()
	return u.udc
}

func (u *UserDelegationKeyRefresher) setUserDelegationKey(udc *service.UserDelegationCredential) {
	u.m.Lock()
	defer u.m.Unlock()
	u.udc = udc
}

func (u *UserDelegationKeyRefresher) refreshUserDelegationKey(ctx context.Context) {
	go func() {
		ticker := time.NewTicker(50 * time.Minute)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				udc, err := u.fetchUserDelegationKey(context.Background())
				if err != nil {
					panic(err)
				}
				u.setUserDelegationKey(udc)
			}
		}
	}()
}

func (u *UserDelegationKeyRefresher) fetchUserDelegationKey(ctx context.Context) (udc *service.UserDelegationCredential, err error) {
	// Create a user delegation key with start time ten seconds ago and expiry time one hour from now
	startTime := time.Now().Add(-10 * time.Second)
	keyStart := startTime.UTC().Format(sas.TimeFormat)
	expiryTime := startTime.Add(1 * time.Hour)
	expiry := expiryTime.UTC().Format(sas.TimeFormat)
	info := service.KeyInfo{
		Start:  &keyStart,
		Expiry: &expiry,
	}

	return u.client.GetUserDelegationCredential(ctx, info, nil)
}
