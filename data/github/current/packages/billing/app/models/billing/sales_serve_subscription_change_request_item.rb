# typed: strict
# frozen_string_literal: true

class Billing::SalesServeSubscriptionChangeRequestItem < ApplicationRecord::Domain::Billing
  belongs_to :change_request, class_name: "Billing::SalesServeSubscriptionChangeRequest", inverse_of: :items, required: true, touch: true

  PRODUCT_GITHUB_ENTERPRISE = "GitHub Enterprise"
  PRODUCT_GITHUB_ADVANCED_SECURITY = "GitHub Advanced Security"

  validates_presence_of :status, :product_rate_plan_charge_id, :change_type, :start_date, :end_date
  validate :validate_removal_of_ghas_seats_allowed_in_renewal_period
  validate :validate_removal_of_ghe_seats_allowed_in_renewal_period

  enum :status, { unknown: 0, pending: 1, error: 2, complete: 3 }, prefix: true
  enum :change_type, { renewal: 1, update: 2 }, prefix: true

  scope :with_start_date, ->(date) { where(start_date: date) }
  scope :with_end_date, ->(date) { where(end_date: date) }
  scope :with_product_rate_plan_charge_id, ->(product_rate_plan_charge_id) { where(product_rate_plan_charge_id: product_rate_plan_charge_id) }
  scope :github_enterprise, -> { with_product_rate_plan_charge_id(GitHub.zuora_sales_serve_ghe_product_charge_ids) }
  scope :github_advanced_security, -> { with_product_rate_plan_charge_id(GitHub.zuora_sales_serve_ghas_product_charge_ids) }

  sig { returns(String) }
  def product
    case product_rate_plan_charge_id
    when *GitHub.zuora_sales_serve_ghe_product_charge_ids
      PRODUCT_GITHUB_ENTERPRISE
    when *GitHub.zuora_sales_serve_ghas_product_charge_ids
      PRODUCT_GITHUB_ADVANCED_SECURITY
    else
      "Unknown"
    end
  end

  private

  sig { void }
  def validate_removal_of_ghe_seats_allowed_in_renewal_period
    business = change_request&.customer&.business

    return unless product == PRODUCT_GITHUB_ENTERPRISE
    return if business.nil?
    return if business.in_renewal_window?
    return if business.seats <= quantity.to_i

    errors.add(:quantity, "can't remove GHE seats outside of a renewal period")
  end

  sig { void }
  def validate_removal_of_ghas_seats_allowed_in_renewal_period
    business = change_request&.customer&.business

    return unless product == PRODUCT_GITHUB_ADVANCED_SECURITY
    return if business.nil?
    return if business.in_renewal_window?
    return if business.advanced_security_seats_for_entity <= quantity.to_i

    errors.add(:quantity, "can't remove GHAS seats outside of a renewal period")
  end
end
