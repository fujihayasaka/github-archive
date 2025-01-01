package models

import (
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/onsi/gomega"
)

func Test_GetPatchOperations_Reactivate(t *testing.T) {
	g := gomega.NewGomegaWithT(t)
	now := UTCNow()
	// give me a usage date from 1 month ago
	startOfMonth := NewUsageTimeFromTime(now.StartOfMonth())
	oneMonthAhead := startOfMonth.AddDay(31)
	currentSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionInactive,
		LicenseSubscriptionAt: startOfMonth,
		LastBilledAt:          startOfMonth,
		UpdatedAt:             startOfMonth,
	}

	newSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionActive,
		LicenseSubscriptionAt: oneMonthAhead,
		UpdatedAt:             oneMonthAhead,
	}

	updater := NewSubscriptionUpdater(currentSubscription, newSubscription)
	po := updater.GetPatchOperations()
	expectedPatchOperations := azcosmos.PatchOperations{}
	expectedPatchOperations.AppendRemove("/last_billed_at")
	expectedPatchOperations.AppendSet("/license_subscription_at", oneMonthAhead)
	expectedPatchOperations.AppendSet("/subscription_status", SubscriptionActive)
	expectedPatchOperations.AppendSet("/updated_at", oneMonthAhead)
	// verify that getPatchOperations returns the correct patch operations
	g.Expect(po).To(gomega.Equal(expectedPatchOperations))
}

func Test_GetPatchOperations_Deactivate(t *testing.T) {
	g := gomega.NewGomegaWithT(t)
	now := UTCNow()
	startOfMonth := NewUsageTimeFromTime(now.StartOfMonth())
	oneMonthAhead := startOfMonth.AddDay(31)
	currentSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionActive,
		LicenseSubscriptionAt: startOfMonth,
		LastBilledAt:          nil,
		UpdatedAt:             startOfMonth,
	}

	newSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionInactive,
		LicenseSubscriptionAt: oneMonthAhead,
		UpdatedAt:             oneMonthAhead,
	}

	updater := NewSubscriptionUpdater(currentSubscription, newSubscription)
	po := updater.GetPatchOperations()
	expectedPatchOperations := azcosmos.PatchOperations{}
	expectedPatchOperations.AppendSet("/last_billed_at", oneMonthAhead)
	expectedPatchOperations.AppendSet("/subscription_status", SubscriptionInactive)
	expectedPatchOperations.AppendSet("/updated_at", oneMonthAhead)
	// verify that getPatchOperations returns the correct patch operations
	g.Expect(po).To(gomega.Equal(expectedPatchOperations))
}

func Test_GetPatchOperations_Duplicate(t *testing.T) {
	g := gomega.NewGomegaWithT(t)
	now := UTCNow()
	startOfMonth := NewUsageTimeFromTime(now.StartOfMonth())
	almostOneMonthAhead := startOfMonth.AddDay(20)
	currentSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionActive,
		LicenseSubscriptionAt: startOfMonth,
		LastBilledAt:          nil,
		UpdatedAt:             startOfMonth,
	}

	newSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionActive,
		LicenseSubscriptionAt: almostOneMonthAhead,
		LastBilledAt:          nil,
		UpdatedAt:             almostOneMonthAhead,
	}

	updater := NewSubscriptionUpdater(currentSubscription, newSubscription)
	po := updater.GetPatchOperations()
	expectedPatchOperations := azcosmos.PatchOperations{}
	g.Expect(po).To(gomega.Equal(expectedPatchOperations))
}

func Test_GetPatchOperations_SubscriptionRollover(t *testing.T) {
	g := gomega.NewGomegaWithT(t)
	startOfMonth := NewUsageTimeFromTime(UTCNow().StartOfMonth())
	oneMonthAhead := startOfMonth.AddDay(31)
	currentSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionActive,
		LicenseSubscriptionAt: startOfMonth,
		LastBilledAt:          nil,
		UpdatedAt:             startOfMonth,
	}

	newSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionActive,
		LicenseSubscriptionAt: oneMonthAhead,
		LastBilledAt:          nil,
		UpdatedAt:             oneMonthAhead,
	}

	updater := NewSubscriptionUpdater(currentSubscription, newSubscription)
	po := updater.GetPatchOperations()
	expectedPatchOperations := azcosmos.PatchOperations{}
	expectedPatchOperations.AppendSet("/updated_at", oneMonthAhead)
	// verify that getPatchOperations returns the correct patch operations
	g.Expect(po).To(gomega.Equal(expectedPatchOperations))
}

func Test_GetPatchOperations_DoubleInactiveDifferentMonths(t *testing.T) {
	g := gomega.NewGomegaWithT(t)
	startOfMonth := NewUsageTimeFromTime(UTCNow().StartOfMonth())
	oneMonthAhead := startOfMonth.AddDay(31)
	currentSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionInactive,
		LicenseSubscriptionAt: startOfMonth,
		LastBilledAt:          nil,
		UpdatedAt:             startOfMonth,
	}

	newSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionInactive,
		LicenseSubscriptionAt: oneMonthAhead,
		LastBilledAt:          nil,
		UpdatedAt:             oneMonthAhead,
	}

	updater := NewSubscriptionUpdater(currentSubscription, newSubscription)
	po := updater.GetPatchOperations()
	expectedPatchOperations := azcosmos.PatchOperations{}
	expectedPatchOperations.AppendSet("/updated_at", oneMonthAhead)
	// verify that getPatchOperations returns the correct patch operations
	g.Expect(po).To(gomega.Equal(expectedPatchOperations))
}

func Test_IsValidForBilling_Duplicate(t *testing.T) {
	g := gomega.NewGomegaWithT(t)
	startOfMonth := NewUsageTimeFromTime(UTCNow().StartOfMonth())
	sameMonth := startOfMonth.AddDay(1)
	currentSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionActive,
		LicenseSubscriptionAt: startOfMonth,
		LastBilledAt:          nil,
		UpdatedAt:             startOfMonth,
	}

	newSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionActive,
		LicenseSubscriptionAt: sameMonth,
		LastBilledAt:          nil,
		UpdatedAt:             sameMonth,
	}

	updater := NewSubscriptionUpdater(currentSubscription, newSubscription)
	isValid := updater.IsValidForBilling()
	g.Expect(isValid).To(gomega.BeFalse())
}

func Test_IsValidForBilling_Inactive(t *testing.T) {
	g := gomega.NewGomegaWithT(t)
	startOfMonth := NewUsageTimeFromTime(UTCNow().StartOfMonth())
	differentMonth := startOfMonth.AddDay(-2)
	currentSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionActive,
		LicenseSubscriptionAt: startOfMonth,
		LastBilledAt:          nil,
		UpdatedAt:             startOfMonth,
	}

	newSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionInactive,
		LicenseSubscriptionAt: differentMonth,
		LastBilledAt:          nil,
		UpdatedAt:             differentMonth,
	}

	updater := NewSubscriptionUpdater(currentSubscription, newSubscription)
	isValid := updater.IsValidForBilling()
	g.Expect(isValid).To(gomega.BeFalse())
}

func Test_IsValidForBilling_ReactivateOnly(t *testing.T) {
	g := gomega.NewGomegaWithT(t)
	startOfMonth := NewUsageTimeFromTime(UTCNow().StartOfMonth())
	differentMonth := startOfMonth.AddDay(-2)
	currentSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionActive,
		LicenseSubscriptionAt: startOfMonth,
		LastBilledAt:          startOfMonth,
		UpdatedAt:             startOfMonth,
	}

	newSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionActive,
		LicenseSubscriptionAt: differentMonth,
		LastBilledAt:          nil,
		UpdatedAt:             differentMonth,
	}

	updater := NewSubscriptionUpdater(currentSubscription, newSubscription)
	isValid := updater.IsValidForBilling()
	g.Expect(isValid).To(gomega.BeTrue())
}

func Test_IsValidForBilling_ReactivateAndSameMonthLicense(t *testing.T) {
	g := gomega.NewGomegaWithT(t)
	startOfMonth := NewUsageTimeFromTime(UTCNow().StartOfMonth())
	sameMonth := startOfMonth.AddDay(2)
	currentSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionInactive,
		LicenseSubscriptionAt: startOfMonth,
		LastBilledAt:          startOfMonth,
		UpdatedAt:             startOfMonth,
	}

	newSubscription := &SubscribedItem{
		SubscriptionStatus:    SubscriptionActive,
		LicenseSubscriptionAt: sameMonth,
		LastBilledAt:          nil,
		UpdatedAt:             sameMonth,
	}

	updater := NewSubscriptionUpdater(currentSubscription, newSubscription)
	isValid := updater.IsValidForBilling()
	g.Expect(isValid).To(gomega.BeFalse())
}
