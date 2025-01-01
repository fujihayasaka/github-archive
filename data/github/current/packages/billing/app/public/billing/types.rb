# typed: strict
# frozen_string_literal: true

module Billing
  # Define billing-wide Sorbet type alias
  module Types
    Account = T.type_alias { T.any(User, Organization, Business) }
    BillingInformation = T.type_alias { T.any(Billing::Contact, AccountScreeningProfile) }

    # Account but only for Organization and Business
    OrgOrBusiness = T.type_alias { T.any(Organization, Business) }

    # Billing::ProductUUID is not included as part of these yet because it doesn't
    # implement the Subscribable module
    Subscribable = T.type_alias do
      T.any(::SponsorsTier, ::Marketplace::ListingPlan)
    end

    SubscribableClasses = T.type_alias do
      T.any(
        T.class_of(::SponsorsTier),
        T.class_of(::Marketplace::ListingPlan)
      )
    end

    NonMoneyNumeric = T.type_alias { T.any(Integer, Float, BigDecimal) }
    Numeric = T.type_alias { T.any(NonMoneyNumeric, Billing::Money) }

    Time = T.type_alias { T.any(::Date, ::Time, ActiveSupport::TimeWithZone) }

    Subscription = T.type_alias do
      T.any(::Billing::PlanSubscription, ::Billing::SalesServePlanSubscription)
    end

    ProposedUsage = T.type_alias do
      T::Array[{
        proposed_quantity:    Numeric,
        entitlement_quantity: Numeric,
        product_sku_name:     T.any(String, Symbol),
        product_name:         T.any(String, Symbol),
      }]
    end
  end
end
