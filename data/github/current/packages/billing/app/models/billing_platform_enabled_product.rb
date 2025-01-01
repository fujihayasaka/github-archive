# typed: strict
# frozen_string_literal: true

class BillingPlatformEnabledProduct < ApplicationRecord::Domain::Users

  include Instrumentation::Model

  after_commit :sync_customer_in_billing_platform, on: [:create, :update]

  validates :customer_id, presence: true, uniqueness: true

  belongs_to :customer

  # overriding the default getter methods so they return false if the value is nil
  # the product columns can have three values:
  # true - enabled
  # false - disabled but was previously enabled
  # nil or null in the database - has never been enabled for this customer

  # overriding these methods also allows us to easily onboard or offboard all customers to a product by setting
  # a default value for any getter method

  sig { returns(T::Boolean) }
  def actions
    self[:actions].present?
  end

  sig { returns(T::Boolean) }
  def git_lfs
    self[:git_lfs].present?
  end

  sig { returns(T::Boolean) }
  def copilot
    self[:copilot].present?
  end

  sig { returns(T::Boolean) }
  def packages
    self[:packages].present?
  end

  sig { returns(T::Boolean) }
  def codespaces
    self[:codespaces].present?
  end

  sig { returns(T::Boolean) }
  def ghec
    self[:ghec].present?
  end

  sig { returns(T::Boolean) }
  def ghas
    self[:ghas].present?
  end

  sig { returns(T::Boolean) }
  def shared_storage
    self[:shared_storage].present?
  end

  sig { returns(T::Array[String]) }
  def all_enabled_products
    products = []

    products << "actions" if actions?
    products << "codespaces" if codespaces?
    products << "copilot" if copilot?
    products << "ghas" if ghas?
    products << "ghec" if ghec?
    products << "git_lfs" if git_lfs?
    products << "packages" if packages?

    products
  end

  # Used to display enabled products in user facing UI - humanized
  sig { returns(T::Array[String]) }
  def all_enabled_products_friendly_names
    products = []

    products << "Actions" if actions?
    products << "Codespaces" if codespaces?
    products << "Copilot" if copilot?
    products << "Advanced Security" if ghas?
    products << "GitHub Enterprise" if ghec?
    products << "Git LFS" if git_lfs?
    products << "Packages" if packages?

    products
  end

  sig { returns(String) }
  def to_sentence
    if all_enabled_products.any?
      all_enabled_products.sort.to_sentence
    else
      "No products enabled"
    end
  end

  private

  sig { void }
  def sync_customer_in_billing_platform
    instrument_billed_via_billing_platform
    Billing::UpdateCustomerInBillingPlatformJob.perform_later(T.must(customer))
  end

  sig { void }
  def instrument_billed_via_billing_platform
    if self.customer&.billed_via_billing_platform?
      instrument :billing_platform_emission_enabled
    else
      instrument :billing_platform_emission_disabled
    end

    GitHub.dogstats.increment("billing.billing_platform_enabled_products_updated.count", tags: dogstats_tags)
  end

  sig { returns(T::Array[String]) }
  def dogstats_tags
    return [] unless self.customer&.present?
    [
      "billable_owner_type:#{self.customer&.billable_owner.class.name}",
      "billing_type:#{self.customer&.billing_type || "none"}",
      "linked_azure_subscription:#{self.customer&.azure_subscription_id.present?}",
      "metered_ghe:#{self.customer&.metered_plan}",
      "metered_via_azure:#{self.customer&.metered_via_azure}",
      "billed_via_billing_platform:#{self.customer&.billed_via_billing_platform}"
    ]
  end
end
