# typed: true
# frozen_string_literal: true

# Handler for SubscriptionCreated webhooks from Zuora
class Billing::Zuora::Webhooks::SubscriptionCreated < ::Billing::Zuora::Webhooks::WebhookHandler
  before_perform :ignore!, if: -> {
    T.bind(self, Billing::Zuora::Webhooks::SubscriptionCreated)

    subscription_not_found? || account_suspended? || not_enterprise_or_organization_subscription?
  }

  def perform
    subscription = T.must(self.subscription)
    if subscription.enterprise?
      Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.new(subscription).sync
    elsif subscription.organization?
      Billing::Zuora::SalesManagedOrganizationSubscriptionSynchronizer.new(subscription).sync
    end
  end

  private

  sig { returns(T.nilable(Billing::Zuora::SalesManagedSubscription)) }
  def subscription
    @subscription ||= T.let(Billing::Zuora::SalesManagedSubscription.fetch_by_subscription_id(subscription_id), T.nilable(Billing::Zuora::SalesManagedSubscription))
  end

  sig { returns(T::Boolean) }
  def subscription_not_found?
    subscription_id.blank? || subscription.blank?
  end

  sig { returns(T::Boolean) }
  def account_suspended?
    # This has the added effect of raising early if the owner is not found
    subscription = self.subscription
    !!(subscription && subscription.owner.suspended?)
  end

  # No-op if neither Dotcom organization ID and enterprise account ID are
  # associated with the subscription. This can happen for GHES-only customers
  # when the initial callout from Zuora fails for some reason and we retry
  # the webhook via `RetrieveFailedZuoraWebhooksJob`.
  sig { returns(T::Boolean) }
  def not_enterprise_or_organization_subscription?
    subscription = self.subscription
    !!(subscription && !subscription.enterprise? && !subscription.organization?)
  end
end
