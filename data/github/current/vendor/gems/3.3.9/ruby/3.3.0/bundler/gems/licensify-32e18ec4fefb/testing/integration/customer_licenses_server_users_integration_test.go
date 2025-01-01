//go:build integration
// +build integration

package integration

import (
	"context"
	"strconv"
	"testing"

	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/internal/utils"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestUpsertAndGetCustomerLicense_ServerUserWithEmail(t *testing.T) {
	client := NewTestClient(t)
	customerLicenseEngine := client.NewCustomerLicenseEngine()

	customerId := stubs.NewRandomID()
	emailAddress := "test@example.com"
	enterpriseInstallationUserAccountId1 := uint64(345)
	enterpriseInstallationUserAccountId2 := uint64(567)

	customerLicense, err := models.NewCustomerLicenseForEnterpriseServerUserWithEmail(customerId, emailAddress)
	require.NoError(t, err)

	customerLicense.Enablements = []*models.CustomerLicenseEnablement{
		{
			Type:   models.ProductEnablementTypeEnterpriseServer,
			Reason: models.EnablementReasonEnterpriseServerUser,
			EnablementIDs: []uint64{
				enterpriseInstallationUserAccountId1,
				enterpriseInstallationUserAccountId2,
			},
		},
	}

	// Upsert the customer license
	err = customerLicenseEngine.Upsert(context.Background(), client.Logger, customerLicense, nil)
	require.NoError(t, err)

	// Fetch it to check
	fetchedCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *customerLicense.Key)
	require.NoError(t, err)

	expectedLicenseeId, err := utils.HashEmail(emailAddress)
	require.NoError(t, err)

	assert.Equal(t, fetchedCustomerLicense.Licensee.Type, models.LicenseeTypeEnterpriseServerUser)
	assert.Equal(t, fetchedCustomerLicense.Licensee.ID, expectedLicenseeId)

	assert.Equal(t, fetchedCustomerLicense.Key.ID, "enterprise-server-user:"+expectedLicenseeId)

	assert.Len(t, fetchedCustomerLicense.Enablements, 1)
	assert.Len(t, fetchedCustomerLicense.Enablements[0].EnablementIDs, 2)

	assert.Contains(t, fetchedCustomerLicense.Enablements[0].EnablementIDs, enterpriseInstallationUserAccountId1)
	assert.Contains(t, fetchedCustomerLicense.Enablements[0].EnablementIDs, enterpriseInstallationUserAccountId2)
}

func TestUpsertAndGetCustomerLicense_ServerUserWithoutEmail(t *testing.T) {
	client := NewTestClient(t)
	customerLicenseEngine := client.NewCustomerLicenseEngine()

	customerId := stubs.NewRandomID()
	enterpriseInstallationUserAccountId := uint64(345)

	customerLicense, err := models.NewCustomerLicenseForEnterpriseServerUserWithoutEmail(customerId, enterpriseInstallationUserAccountId)
	require.NoError(t, err)

	customerLicense.Enablements = []*models.CustomerLicenseEnablement{
		{
			Type:          models.ProductEnablementTypeEnterpriseServer,
			Reason:        models.EnablementReasonEnterpriseServerUser,
			EnablementIDs: []uint64{enterpriseInstallationUserAccountId},
		},
	}

	// Upsert the customer license
	err = customerLicenseEngine.Upsert(context.Background(), client.Logger, customerLicense, nil)
	require.NoError(t, err)

	// Fetch it to check
	fetchedCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *customerLicense.Key)
	require.NoError(t, err)

	expectedLicenseeId, err := utils.HashUint64(enterpriseInstallationUserAccountId)
	require.NoError(t, err)

	assert.Equal(t, fetchedCustomerLicense.Licensee.Type, models.LicenseeTypeEnterpriseServerUser)
	assert.Equal(t, fetchedCustomerLicense.Licensee.ID, expectedLicenseeId)

	assert.Equal(t, fetchedCustomerLicense.Key.ID, "enterprise-server-user:"+expectedLicenseeId)

	assert.Len(t, fetchedCustomerLicense.Enablements, 1)
	assert.Len(t, fetchedCustomerLicense.Enablements[0].EnablementIDs, 1)

	assert.Contains(t, fetchedCustomerLicense.Enablements[0].EnablementIDs, enterpriseInstallationUserAccountId)
}

func TestUpsertAndGetCustomerLicense_CloudUserWithServerEnablements(t *testing.T) {
	client := NewTestClient(t)
	customerLicenseEngine := client.NewCustomerLicenseEngine()

	customerId := stubs.NewRandomID()
	userId := stubs.NewRandomID()
	licenseeId := strconv.FormatUint(userId, 10)
	enterpriseInstallationUserAccountId1 := uint64(345)
	enterpriseInstallationUserAccountId2 := uint64(567)

	customerLicense := models.NewCustomerLicenseForUserWithMemberships(customerId, userId, nil, nil)
	customerLicense.Enablements = []*models.CustomerLicenseEnablement{
		{
			Type:          models.ProductEnablementTypeEnterpriseServer,
			Reason:        models.EnablementReasonEnterpriseServerUser,
			EnablementIDs: []uint64{enterpriseInstallationUserAccountId1, enterpriseInstallationUserAccountId2},
		},
	}

	// Upsert the customer license
	err := customerLicenseEngine.Upsert(context.Background(), client.Logger, customerLicense, nil)
	require.NoError(t, err)

	// Fetch it to check
	fetchedCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *customerLicense.Key)
	require.NoError(t, err)

	assert.Equal(t, fetchedCustomerLicense.Licensee.Type, models.LicenseeTypeUser)
	assert.Equal(t, fetchedCustomerLicense.Licensee.ID, licenseeId)

	assert.Equal(t, fetchedCustomerLicense.Key.ID, "user:"+licenseeId)

	assert.Len(t, fetchedCustomerLicense.Enablements, 1)
	assert.Len(t, fetchedCustomerLicense.Enablements[0].EnablementIDs, 2)

	assert.Contains(t, fetchedCustomerLicense.Enablements[0].EnablementIDs, enterpriseInstallationUserAccountId1)
	assert.Contains(t, fetchedCustomerLicense.Enablements[0].EnablementIDs, enterpriseInstallationUserAccountId2)
}

func TestUpdateCustomerLicense_ServerUserWithoutEmailGetsEmail(t *testing.T) {
	client := NewTestClient(t)
	customerLicenseEngine := client.NewCustomerLicenseEngine()

	customerId := stubs.NewRandomID()
	enterpriseInstallationUserAccountId := uint64(345)

	firstCustomerLicense, err := models.NewCustomerLicenseForEnterpriseServerUserWithoutEmail(customerId, enterpriseInstallationUserAccountId)
	require.NoError(t, err)

	firstCustomerLicense.Enablements = []*models.CustomerLicenseEnablement{
		{
			Type:          models.ProductEnablementTypeEnterpriseServer,
			Reason:        models.EnablementReasonEnterpriseServerUser,
			EnablementIDs: []uint64{enterpriseInstallationUserAccountId},
		},
	}

	// Upsert the first customer license
	err = customerLicenseEngine.Upsert(context.Background(), client.Logger, firstCustomerLicense, nil)
	require.NoError(t, err)

	// Fetch it to check
	fetchedFirstCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *firstCustomerLicense.Key)
	require.NoError(t, err)

	// Oh, now we got an email. Let's make a new license with the email
	emailAddress := "foo@bar.com"

	newCustomerLicense, err := models.NewCustomerLicenseForEnterpriseServerUserWithEmail(customerId, emailAddress)
	require.NoError(t, err)

	newCustomerLicense.Enablements = fetchedFirstCustomerLicense.Enablements

	// Swap the license documents
	err = customerLicenseEngine.Swap(context.Background(), client.Logger, fetchedFirstCustomerLicense, newCustomerLicense, nil)
	require.NoError(t, err)

	// Fetch the new one to check
	fetchedNewCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *newCustomerLicense.Key)
	require.NoError(t, err)

	expectedLicenseeId, err := utils.HashEmail(emailAddress)
	require.NoError(t, err)

	assert.Equal(t, fetchedNewCustomerLicense.Licensee.Type, models.LicenseeTypeEnterpriseServerUser)
	assert.Equal(t, fetchedNewCustomerLicense.Licensee.ID, expectedLicenseeId)

	assert.Equal(t, fetchedNewCustomerLicense.Key.ID, "enterprise-server-user:"+expectedLicenseeId)

	// Fetch the old one to check that it is not there anymore
	goneLicense, err := customerLicenseEngine.Get(context.Background(), *firstCustomerLicense.Key)
	require.NoError(t, err)

	assert.Nil(t, goneLicense)
}

func TestUpdateCustomerLicense_ServerUserWithEmailLosesEmail(t *testing.T) {
	client := NewTestClient(t)
	customerLicenseEngine := client.NewCustomerLicenseEngine()

	customerId := stubs.NewRandomID()
	emailAddress := "foo@example.com"
	enterpriseInstallationUserAccountId := uint64(345)

	firstCustomerLicense, err := models.NewCustomerLicenseForEnterpriseServerUserWithEmail(customerId, emailAddress)
	require.NoError(t, err)

	firstCustomerLicense.Enablements = []*models.CustomerLicenseEnablement{
		{
			Type:          models.ProductEnablementTypeEnterpriseServer,
			Reason:        models.EnablementReasonEnterpriseServerUser,
			EnablementIDs: []uint64{enterpriseInstallationUserAccountId},
		},
	}

	// Upsert the first customer license
	err = customerLicenseEngine.Upsert(context.Background(), client.Logger, firstCustomerLicense, nil)
	require.NoError(t, err)

	// Fetch it to check
	fetchedFirstCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *firstCustomerLicense.Key)
	require.NoError(t, err)

	// Oh, now we lost the email. Let's make a new license without the email
	newCustomerLicense, err := models.NewCustomerLicenseForEnterpriseServerUserWithoutEmail(customerId, enterpriseInstallationUserAccountId)
	require.NoError(t, err)

	newCustomerLicense.Enablements = fetchedFirstCustomerLicense.Enablements

	// Swap the license documents
	err = customerLicenseEngine.Swap(context.Background(), client.Logger, fetchedFirstCustomerLicense, newCustomerLicense, nil)
	require.NoError(t, err)

	// Fetch the new one to check
	fetchedNewCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *newCustomerLicense.Key)
	require.NoError(t, err)

	expectedLicenseeId, err := utils.HashUint64(enterpriseInstallationUserAccountId)
	require.NoError(t, err)

	assert.Equal(t, fetchedNewCustomerLicense.Licensee.Type, models.LicenseeTypeEnterpriseServerUser)
	assert.Equal(t, fetchedNewCustomerLicense.Licensee.ID, expectedLicenseeId)

	assert.Equal(t, fetchedNewCustomerLicense.Key.ID, "enterprise-server-user:"+expectedLicenseeId)

	// Fetch the old one to check that it is not there anymore
	goneLicense, err := customerLicenseEngine.Get(context.Background(), *firstCustomerLicense.Key)
	require.NoError(t, err)

	assert.Nil(t, goneLicense)
}

func TestUpdateCustomerLicense_ServerUserWithEmailGetsLinkedToCloudUser(t *testing.T) {
	client := NewTestClient(t)
	customerLicenseEngine := client.NewCustomerLicenseEngine()

	customerId := stubs.NewRandomID()
	emailAddress := "foo@example.com"

	enterpriseInstallationUserAccountId := uint64(345)
	cloudUserId := stubs.NewRandomID()

	firstCustomerLicense, err := models.NewCustomerLicenseForEnterpriseServerUserWithEmail(customerId, emailAddress)
	require.NoError(t, err)

	firstCustomerLicense.Enablements = []*models.CustomerLicenseEnablement{
		{
			Type:          models.ProductEnablementTypeEnterpriseServer,
			Reason:        models.EnablementReasonEnterpriseServerUser,
			EnablementIDs: []uint64{enterpriseInstallationUserAccountId},
		},
	}

	// Upsert the first customer license
	err = customerLicenseEngine.Upsert(context.Background(), client.Logger, firstCustomerLicense, nil)
	require.NoError(t, err)

	// Fetch it to check
	fetchedFirstCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *firstCustomerLicense.Key)
	require.NoError(t, err)

	// Oh, now we got a cloud user. Let's make a new license with the cloud user
	newCustomerLicense := models.NewCustomerLicenseForUserWithMemberships(customerId, cloudUserId, nil, nil)
	newCustomerLicense.Enablements = fetchedFirstCustomerLicense.Enablements

	// Swap the license documents
	err = customerLicenseEngine.Swap(context.Background(), client.Logger, fetchedFirstCustomerLicense, newCustomerLicense, nil)
	require.NoError(t, err)

	// Fetch the new one to check
	fetchedNewCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *newCustomerLicense.Key)
	require.NoError(t, err)

	assert.Equal(t, fetchedNewCustomerLicense.Licensee.Type, models.LicenseeTypeUser)
	assert.Equal(t, fetchedNewCustomerLicense.Licensee.ID, strconv.FormatUint(cloudUserId, 10))

	assert.Equal(t, fetchedNewCustomerLicense.Key.ID, "user:"+strconv.FormatUint(cloudUserId, 10))

	// Fetch the old one to check that it is not there anymore
	goneLicense, err := customerLicenseEngine.Get(context.Background(), *firstCustomerLicense.Key)
	require.NoError(t, err)

	assert.Nil(t, goneLicense)
}

func TestUpdateCustomerLicense_ServerUserWithoutEmailGetsCloudUser(t *testing.T) {
	client := NewTestClient(t)
	customerLicenseEngine := client.NewCustomerLicenseEngine()

	customerId := stubs.NewRandomID()
	enterpriseInstallationUserAccountId := uint64(345)
	cloudUserId := stubs.NewRandomID()

	firstCustomerLicense, err := models.NewCustomerLicenseForEnterpriseServerUserWithoutEmail(customerId, enterpriseInstallationUserAccountId)
	require.NoError(t, err)

	firstCustomerLicense.Enablements = []*models.CustomerLicenseEnablement{
		{
			Type:          models.ProductEnablementTypeEnterpriseServer,
			Reason:        models.EnablementReasonEnterpriseServerUser,
			EnablementIDs: []uint64{enterpriseInstallationUserAccountId},
		},
	}

	// Upsert the first customer license
	err = customerLicenseEngine.Upsert(context.Background(), client.Logger, firstCustomerLicense, nil)
	require.NoError(t, err)

	// Fetch it to check
	fetchedFirstCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *firstCustomerLicense.Key)
	require.NoError(t, err)

	// Oh, now we got a cloud user. Let's make a new license with the cloud user
	newCustomerLicense := models.NewCustomerLicenseForUserWithMemberships(customerId, cloudUserId, nil, nil)
	newCustomerLicense.Enablements = fetchedFirstCustomerLicense.Enablements

	// Swap the license documents
	err = customerLicenseEngine.Swap(context.Background(), client.Logger, fetchedFirstCustomerLicense, newCustomerLicense, nil)
	require.NoError(t, err)

	// Fetch the new one to check
	fetchedNewCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *newCustomerLicense.Key)
	require.NoError(t, err)

	assert.Equal(t, fetchedNewCustomerLicense.Licensee.Type, models.LicenseeTypeUser)
	assert.Equal(t, fetchedNewCustomerLicense.Licensee.ID, strconv.FormatUint(cloudUserId, 10))

	assert.Equal(t, fetchedNewCustomerLicense.Key.ID, "user:"+strconv.FormatUint(cloudUserId, 10))

	// Fetch the old one to check that it is not there anymore
	goneLicense, err := customerLicenseEngine.Get(context.Background(), *firstCustomerLicense.Key)
	require.NoError(t, err)

	assert.Nil(t, goneLicense)
}

func TestUpdateCustomerLicense_CloudUserWithServerUserAndEmailLosesCloudUser(t *testing.T) {
	client := NewTestClient(t)
	customerLicenseEngine := client.NewCustomerLicenseEngine()

	customerId := stubs.NewRandomID()
	emailAddress := "test@example.com"
	enterpriseInstallationUserAccountId := uint64(345)
	cloudUserId := stubs.NewRandomID()

	firstCustomerLicense := models.NewCustomerLicenseForUserWithMemberships(customerId, cloudUserId, nil, nil)
	firstCustomerLicense.Enablements = []*models.CustomerLicenseEnablement{
		{
			Type:          models.ProductEnablementTypeEnterpriseServer,
			Reason:        models.EnablementReasonEnterpriseServerUser,
			EnablementIDs: []uint64{enterpriseInstallationUserAccountId},
		},
	}

	// Upsert the first customer license
	err := customerLicenseEngine.Upsert(context.Background(), client.Logger, firstCustomerLicense, nil)
	require.NoError(t, err)

	// Fetch it to check
	fetchedFirstCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *firstCustomerLicense.Key)
	require.NoError(t, err)

	// Oh, now we lost the cloud user. Let's make a new license without the cloud user.
	// We should keep the email, which should be available at this point via data pulled from dotcom.
	newCustomerLicense, err := models.NewCustomerLicenseForEnterpriseServerUserWithEmail(customerId, emailAddress)
	require.NoError(t, err)

	// We lose the cloud user enablement but keep the server user enablement
	newCustomerLicense.Enablements = []*models.CustomerLicenseEnablement{
		{
			Type:          models.ProductEnablementTypeEnterpriseServer,
			Reason:        models.EnablementReasonEnterpriseServerUser,
			EnablementIDs: []uint64{enterpriseInstallationUserAccountId},
		},
	}

	// Swap the license documents
	err = customerLicenseEngine.Swap(context.Background(), client.Logger, fetchedFirstCustomerLicense, newCustomerLicense, nil)
	require.NoError(t, err)

	// Fetch the new one to check
	fetchedNewCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *newCustomerLicense.Key)
	require.NoError(t, err)

	expectedLicenseeId, err := utils.HashEmail(emailAddress)
	require.NoError(t, err)

	assert.Equal(t, fetchedNewCustomerLicense.Licensee.Type, models.LicenseeTypeEnterpriseServerUser)
	assert.Equal(t, fetchedNewCustomerLicense.Licensee.ID, expectedLicenseeId)

	assert.Equal(t, fetchedNewCustomerLicense.Key.ID, "enterprise-server-user:"+expectedLicenseeId)

	// Fetch the old one to check that it is not there anymore
	goneLicense, err := customerLicenseEngine.Get(context.Background(), *firstCustomerLicense.Key)
	require.NoError(t, err)

	assert.Nil(t, goneLicense)
}

func TestUpdateCustomerLicense_CloudUserWithServerUserAndNoEmailLosesCloudUser(t *testing.T) {
	client := NewTestClient(t)
	customerLicenseEngine := client.NewCustomerLicenseEngine()

	customerId := stubs.NewRandomID()
	enterpriseInstallationUserAccountId := uint64(345)
	cloudUserId := stubs.NewRandomID()

	firstCustomerLicense := models.NewCustomerLicenseForUserWithMemberships(customerId, cloudUserId, nil, nil)
	firstCustomerLicense.Enablements = []*models.CustomerLicenseEnablement{
		{
			Type:          models.ProductEnablementTypeEnterpriseServer,
			Reason:        models.EnablementReasonEnterpriseServerUser,
			EnablementIDs: []uint64{enterpriseInstallationUserAccountId},
		},
	}

	// Upsert the first customer license
	err := customerLicenseEngine.Upsert(context.Background(), client.Logger, firstCustomerLicense, nil)
	require.NoError(t, err)

	// Fetch it to check
	fetchedFirstCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *firstCustomerLicense.Key)
	require.NoError(t, err)

	// Oh, now we lost the cloud user. Let's make a new license without the cloud user.
	// Act as if the data we get from dotcom for this user does not have an email, also.
	newCustomerLicense, err := models.NewCustomerLicenseForEnterpriseServerUserWithoutEmail(customerId, enterpriseInstallationUserAccountId)
	require.NoError(t, err)

	// We lose the cloud user enablement but keep the server user enablement
	newCustomerLicense.Enablements = []*models.CustomerLicenseEnablement{
		{
			Type:          models.ProductEnablementTypeEnterpriseServer,
			Reason:        models.EnablementReasonEnterpriseServerUser,
			EnablementIDs: []uint64{enterpriseInstallationUserAccountId},
		},
	}

	// Swap the license documents
	err = customerLicenseEngine.Swap(context.Background(), client.Logger, fetchedFirstCustomerLicense, newCustomerLicense, nil)
	require.NoError(t, err)

	// Fetch the new one to check
	fetchedNewCustomerLicense, err := customerLicenseEngine.Get(context.Background(), *newCustomerLicense.Key)
	require.NoError(t, err)

	expectedLicenseeId, err := utils.HashUint64(enterpriseInstallationUserAccountId)
	require.NoError(t, err)

	assert.Equal(t, fetchedNewCustomerLicense.Licensee.Type, models.LicenseeTypeEnterpriseServerUser)
	assert.Equal(t, fetchedNewCustomerLicense.Licensee.ID, expectedLicenseeId)

	assert.Equal(t, fetchedNewCustomerLicense.Key.ID, "enterprise-server-user:"+expectedLicenseeId)

	// Fetch the old one to check that it is not there anymore
	goneLicense, err := customerLicenseEngine.Get(context.Background(), *firstCustomerLicense.Key)
	require.NoError(t, err)

	assert.Nil(t, goneLicense)
}
