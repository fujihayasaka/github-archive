package interfaces

import "github.com/github/billing-platform/lib/models"

type PricingApplicator interface {
	ApplyPricing(currentPricing *models.Pricing)
	GetSku() string
}
