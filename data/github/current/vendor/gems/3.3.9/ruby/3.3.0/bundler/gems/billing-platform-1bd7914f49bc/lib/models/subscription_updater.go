package models

import (
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
)

type SubscriptionUpdater struct {
	currentSubscription *SubscribedItem
	newSubscription     *SubscribedItem
}

func NewSubscriptionUpdater(currentSubscription *SubscribedItem, newSubscription *SubscribedItem) *SubscriptionUpdater {
	return &SubscriptionUpdater{
		currentSubscription: currentSubscription,
		newSubscription:     newSubscription,
	}
}

func (u SubscriptionUpdater) GetPatchOperations() azcosmos.PatchOperations {
	po := azcosmos.PatchOperations{}
	usageDate := u.newSubscription.UpdatedAt
	switch {
	case u.shouldReactivateSubscription():
		po.AppendRemove("/last_billed_at")
		po.AppendSet("/license_subscription_at", usageDate)
		po.AppendSet("/subscription_status", SubscriptionActive)
	case u.shouldDeactivateSubscription():
		po.AppendSet("/last_billed_at", usageDate)
		po.AppendSet("/subscription_status", SubscriptionInactive)
	case u.isDuplicate():
		return po
	default: // new month for existing subscription
	}

	po.AppendSet("/updated_at", usageDate)

	return po
}

func (u SubscriptionUpdater) IsValidForBilling() bool {
	if u.isDuplicate() || u.newSubscription.SubscriptionStatus == SubscriptionInactive ||
		(u.shouldReactivateSubscription() && u.currentSubscription.LastBilledAt.IsInSameYearAndMonth(u.newSubscription.LicenseSubscriptionAt)) {
		return false
	}

	return true
}

func (u SubscriptionUpdater) shouldDeactivateSubscription() bool {
	return u.newSubscription.SubscriptionStatus == SubscriptionInactive && u.currentSubscription.SubscriptionStatus == SubscriptionActive
}

func (u SubscriptionUpdater) shouldReactivateSubscription() bool {
	return u.newSubscription.SubscriptionStatus == SubscriptionActive && u.currentSubscription.LastBilledAt != nil
}

func (u SubscriptionUpdater) isDuplicate() bool {
	return u.currentSubscription.SubscriptionStatus == u.newSubscription.SubscriptionStatus &&
		u.currentSubscription.UpdatedAt.IsInSameYearAndMonth(u.newSubscription.UpdatedAt)
}
