# typed: true
# frozen_string_literal: true

class Billing::PrepaidMeteredUsageRefill < ApplicationRecord::Domain::Billing
  include Instrumentation::Model

  self.table_name = "billing_prepaid_metered_usage_refills"
  belongs_to :owner, polymorphic: true

  validates :expires_on, presence: true
  validates :amount_in_subunits, presence: true
  validates :currency_code, presence: true
  validates :zuora_rate_plan_charge_id, uniqueness: { case_sensitive: false, allow_nil: true }

  scope :expired, -> { where("expires_on < :now", now: GitHub::Billing.now) }

  after_create_commit :log_create_event

  def self.enabled_for?(owner)
    return owner.pays_github_directly? if owner.is_a?(Business)
    owner.organization? &&
      owner.invoiced? &&
      !owner.delegate_billing_to_business?
  end

  def self.total_active_amount_in_cents_for(owner:)
    Billing::PrepaidMeteredUsageRefill.where(owner: owner).sum(:amount_in_subunits)
  end

  def staff_created?
    zuora_rate_plan_charge_id.blank?
  end

  private

  def event_prefix
    :prepaid_metered_refill
  end

  # Default values to passed to events created by #instrument
  def event_payload
    payload = {
      amount_in_subunits: amount_in_subunits,
      currency_code: currency_code,
      expires_on: expires_on,
      staff_created: zuora_rate_plan_charge_id.nil?,
    }

    if owner.is_a?(Business)
      payload[:business] = owner
    elsif owner.is_a?(Organization)
      payload[:org] = owner
    else
      payload[:user] = owner
    end

    payload
  end

  def log_create_event
    instrument :create
  end
end
