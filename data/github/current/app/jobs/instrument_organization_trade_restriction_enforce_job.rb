# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class InstrumentOrganizationTradeRestrictionEnforceJob < ApplicationJob
  queue_as :trade_controls
  retry_on_dirty_exit

  discard_on ActiveJob::DeserializationError do |_job, error|
    Failbot.report(error)
  end

  # actor is nil if this is an automated org flagging
  def perform(
    organization:,
    enforcement_date: nil,
    subscriber: "trade_restriction.organization_enforce",
    actor: nil,
    country: nil,
    reason:,
    website_url: nil,
    email: nil,
    region: nil,
    percentage_of_trade_restricted_members: nil,
    percentage_of_trade_restricted_billing_managers: nil,
    percentage_of_trade_restricted_admins: nil,
    restricted_on_creation: false,
    last_enforcement_date: nil,
    last_override_date: nil
  )

    @organization = organization
    @enforcement_date = enforcement_date
    @reason = reason
    @actor = actor
    @website_url = website_url
    @email = email
    @region = region
    @percentage_of_trade_restricted_admins = percentage_of_trade_restricted_admins
    @percentage_of_trade_restricted_billing_managers = percentage_of_trade_restricted_billing_managers
    @percentage_of_trade_restricted_members = percentage_of_trade_restricted_members
    @restricted_on_creation = restricted_on_creation
    @last_enforcement_date = last_enforcement_date
    @last_override_date = last_override_date

    GlobalInstrumenter.instrument(subscriber, trade_restriction_enforce_payload)
  end

  private

  def trade_restriction_base_payload
    payload = {
      organization: @organization,
      organization_member_count: @organization.members_count,
      organization_public_repos_count: @organization.public_repositories.count,
      organization_private_repos_count: @organization.private_repositories.count,
      organization_trade_restricted_member_count: @organization.trade_controls_restricted_members.count,
      organization_time_since_creation_in_days: org_time_since_creation_in_days,
      organization_total_paid_amount_in_cents: org_organization_total_paid_amount_in_cents,
      percentage_of_trade_restricted_billing_managers: @percentage_of_trade_restricted_billing_managers,
      percentage_of_trade_restricted_admins: @percentage_of_trade_restricted_admins,
      percentage_of_trade_restricted_members: @percentage_of_trade_restricted_members,
    }
  end

  def trade_restriction_enforce_payload
    payload = trade_restriction_base_payload
    payload[:actor] = @actor
    payload[:restriction_reason] = @reason
    payload[:website_url] = @website_url
    payload[:email_address] = @email
    payload[:region] = @region
    payload[:restricted_on_creation] = @restricted_on_creation
    payload[:last_enforcement_date] = @last_enforcement_date
    payload[:last_override_date] = @last_override_date
    payload
  end

  def org_time_since_creation_in_days
    (Date.current - @organization.created_at.to_date).to_i
  end

  def org_organization_total_paid_amount_in_cents
    @organization.billing_transactions.
      where(
        "billing_transactions.amount_in_cents > 0",
        last_status: Billing::BillingTransactionStatuses::SUCCESS.values,
      ).sum(:amount_in_cents)
  end
end
