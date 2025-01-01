# typed: true
# frozen_string_literal: true

module User::MarketplaceDependency
  PENDING_INSTALLATIONS_NOTICE_TRIGGERED_AFTER = 7.days

  def verified_for_repo_actions?
    false # Users cannot be verified
  end

  def creator_verification_state?
    # users can not get verified creator tag
    Configurable::MarketplaceCreatorVerification::DEFAULT
  end

  def pending_marketplace_installations(only_notice_triggered: false)
    subscription_items = Billing::SubscriptionItem.with_marketplace_listing_plans_type.
      joins(:plan_subscription).
      where(plan_subscriptions: { user_id: T.unsafe(self).user_or_adminable_org_ids }).
      not_installed.
      active

    subscribable_ids = subscription_items.distinct.pluck(:subscribable_id)
    return Billing::SubscriptionItem.none if subscribable_ids.empty?

    marketplace_listing_plans_ids = Marketplace::ListingPlan.joins(:listing)
      .where(id: subscribable_ids)
      .pluck(:id)
    return Billing::SubscriptionItem.none if marketplace_listing_plans_ids.empty?

    relation = subscription_items.where(subscribable_id: marketplace_listing_plans_ids)

    if only_notice_triggered
      dismissed_at = Marketplace::PendingInstallations::Notice.new(user_id: T.unsafe(self).id).dismissed_at

      if dismissed_at
        relation = relation.purchased_between(dismissed_at, PENDING_INSTALLATIONS_NOTICE_TRIGGERED_AFTER.ago)
      else
        relation = relation.purchased_before(PENDING_INSTALLATIONS_NOTICE_TRIGGERED_AFTER.ago)
      end
    end

    relation
  end
end
