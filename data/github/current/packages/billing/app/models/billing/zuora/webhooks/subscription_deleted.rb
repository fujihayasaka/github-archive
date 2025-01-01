# typed: true
# frozen_string_literal: true

# Handler for SubscriptionDeleted webhooks from Zuora
class Billing::Zuora::Webhooks::SubscriptionDeleted < ::Billing::Zuora::Webhooks::WebhookHandler
  before_perform :ignore!, if: -> do
    T.bind(self, Billing::Zuora::Webhooks::SubscriptionDeleted)
    plan_subscription.nil?
  end

  def perform
    T.must(plan_subscription).clear_external_subscription_references

    instrument_webhook
  end

  private

  sig { void }
  def instrument_webhook
    plan_subscription = T.must(self.plan_subscription)
    tags = []
    if sales_serve_subscription
      tags << "subscription_type:sales_serve"
    else
      tags << "subscription_type:self_serve"
    end

    account = plan_subscription.billable_entity
    if account
      billing_type = account.invoiced? ? "invoiced" : "self_serve"
      tags << "billing_type:#{billing_type}"
      tags << "zuora_ent_account_id_present:#{payload["DotcomEntAccountId__c"].present?}"
      tags << "zuora_org_id_present:#{payload["DotcomOrgId__c"].present?}"
      if account.business?
        tags << "account_type:business"

        account_matches = account.id.to_s == payload["DotcomEntAccountId__c"].to_s
        tags << "account_matches:#{account_matches}"
      else
        tags << "account_type:organization"

        account_matches = account.id.to_s == payload["DotcomOrgId__c"].to_s
        tags << "account_matches:#{account_matches}"
      end
    else
      tags << "billing_type:unknown"
      tags << "account_type:unknown"
    end

    GitHub.dogstats.increment("billing.zuora_webhooks.subscription_deleted", tags: tags)
  end

  sig { returns(T.nilable(T.any(::Billing::SalesServePlanSubscription, ::Billing::PlanSubscription))) }
  def plan_subscription
    @plan_subscription ||= T.let(sales_serve_subscription || self_serve_subscription, T.nilable(T.any(::Billing::SalesServePlanSubscription, ::Billing::PlanSubscription)))
  end

  sig { returns(T.nilable(::Billing::SalesServePlanSubscription)) }
  def sales_serve_subscription
    @sales_serve_subscription ||= T.let(::Billing::SalesServePlanSubscription.find_by(
      zuora_subscription_id: payload["subscription_id"]
    ), T.nilable(::Billing::SalesServePlanSubscription))
  end

  sig { returns(T.nilable(::Billing::PlanSubscription)) }
  def self_serve_subscription
    @self_serve_subscription ||= T.let(::Billing::PlanSubscription.find_by(
      zuora_subscription_id: payload["subscription_id"]
    ), T.nilable(::Billing::PlanSubscription))
  end
end
