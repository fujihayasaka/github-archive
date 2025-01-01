//go:build integration
// +build integration

package eventhandlers_test

import (
	"context"
	"strconv"
	"testing"
	"time"

	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/testing/integration"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDocumentsAreDeletedWhenUserIsDestroyed(t *testing.T) {
	client := integration.NewTestClient(t)
	handler := client.EventHandler

	customerEngine := engines.NewCustomerEngine(
		client.Statter,
		client.Tracer,
		client.DB,
	)

	customerLicenseEngine := engines.NewCustomerLicenseEngine(
		client.Statter,
		client.Tracer,
		client.DB,
	)
	licenseeLicenseEngine := engines.NewLicenseeLicenseEngine(
		client.Statter,
		client.Tracer,
		client.DB,
	)

	msg := stubs.NewUserDestroyHydroMsg()
	userID := msg.GetUser().GetId()
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	customerID := uint64(1)
	customer := models.NewCustomer(
		customerID,
		models.LicensingModelVolume,
		false,
	)

	licensee := models.NewLicensee(
		models.LicenseeTypeUser,
		licenseeID,
	)

	licenseeLicense := models.NewLicenseeLicense(
		licensee,
		models.ProductSDLC,
		models.LicenseStatusActive,
		customerID,
		time.Now().Add(time.Hour*24*30).Unix(),
		nil,
	)

	require.NoError(t, customerEngine.Upsert(
		context.Background(),
		client.Logger,
		customer,
		nil,
	))

	require.NoError(t, licenseeLicenseEngine.Upsert(
		context.Background(),
		client.Logger,
		licenseeLicense,
		nil,
	))

	require.NoError(t, customerLicenseEngine.Upsert(
		context.Background(),
		client.Logger,
		licenseeLicense.BuildCustomerLicense(),
		nil,
	))

	// make sure licensee license exists prior to deletion
	ogLicenses, _ := licenseeLicenseEngine.GetAll(context.Background(), client.Logger, userID)
	assert.Len(t, ogLicenses, 1)

	_, herr := handler.HandleUserDestroy(context.Background(), client.Logger, msg)
	require.NoError(t, herr.Err)

	removedLicenseeLicenses, _ := licenseeLicenseEngine.GetAll(context.Background(), client.Logger, userID)
	assert.Len(t, removedLicenseeLicenses, 0)
	removedCustomerLicenses, _ := customerLicenseEngine.GetAll(context.Background(), client.Logger, customerID, models.ProductSDLC)
	assert.Len(t, removedCustomerLicenses, 0)
}

func TestDocumentsAreExpiredWhenUserIsDestroyed(t *testing.T) {
	client := integration.NewTestClient(t)
	handler := client.EventHandler

	// Mock the now time var to freeze time to currentTime
	currentTime := time.Now().UTC()
	models.Now = func() time.Time {
		return currentTime
	}
	year, month, _ := currentTime.Date()
	nextMonth := time.Date(year, month+1, 1, 0, 0, 0, 0, currentTime.Location())
	expectedRemainingSeconds := int64(nextMonth.Sub(currentTime).Seconds())

	customerEngine := engines.NewCustomerEngine(
		client.Statter,
		client.Tracer,
		client.DB,
	)

	customerLicenseEngine := engines.NewCustomerLicenseEngine(
		client.Statter,
		client.Tracer,
		client.DB,
	)
	licenseeLicenseEngine := engines.NewLicenseeLicenseEngine(
		client.Statter,
		client.Tracer,
		client.DB,
	)

	msg := stubs.NewUserDestroyHydroMsg()
	userID := msg.GetUser().GetId()
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	customerID := uint64(1)
	customer := models.NewCustomer(
		customerID,
		models.LicensingModelMetered,
		false,
	)

	licensee := models.NewLicensee(
		models.LicenseeTypeUser,
		licenseeID,
	)

	licenseeLicense := models.NewLicenseeLicense(
		licensee,
		models.ProductSDLC,
		models.LicenseStatusActive,
		customerID,
		time.Now().Add(time.Hour*24*30).Unix(),
		nil,
	)

	require.NoError(t, customerEngine.Upsert(
		context.Background(),
		client.Logger,
		customer,
		nil,
	))

	require.NoError(t, licenseeLicenseEngine.Upsert(
		context.Background(),
		client.Logger,
		licenseeLicense,
		nil,
	))

	require.NoError(t, customerLicenseEngine.Upsert(
		context.Background(),
		client.Logger,
		licenseeLicense.BuildCustomerLicense(),
		nil,
	))

	// make sure licensee license exists prior to deletion
	ogLicenses, _ := licenseeLicenseEngine.GetAll(context.Background(), client.Logger, userID)
	assert.Len(t, ogLicenses, 1)

	_, herr := handler.HandleUserDestroy(context.Background(), client.Logger, msg)
	require.NoError(t, herr.Err)

	removedLicenseeLicenses, _ := licenseeLicenseEngine.GetAll(context.Background(), client.Logger, userID)
	assert.Len(t, removedLicenseeLicenses, 1)
	assert.Equal(t, models.LicenseStatusDeactivated, removedLicenseeLicenses[0].LicenseStatus)
	assert.Equal(t, models.EndOfMonth(), removedLicenseeLicenses[0].ExpiresAt)
	assert.Equal(t, expectedRemainingSeconds, *removedLicenseeLicenses[0].TTL)

	removedCustomerLicenses, _ := customerLicenseEngine.GetAll(context.Background(), client.Logger, customerID, models.ProductSDLC)
	assert.Len(t, removedCustomerLicenses, 1)
	assert.Equal(t, models.LicenseStatusDeactivated, removedCustomerLicenses[0].LicenseStatus)
	assert.Equal(t, models.EndOfMonth(), removedCustomerLicenses[0].ExpiresAt)
	assert.Equal(t, expectedRemainingSeconds, *removedCustomerLicenses[0].TTL)
}
