# typed: strict
# frozen_string_literal: true

module Billing
  class BillingTransaction::LineItem < ApplicationRecord::Domain::Users
    extend T::Sig

    include BillingTransaction::LineItem::SponsorsDependency
    include GitHub::Validations

    ACTIONS_PRIVATE_USAGE_DESCRIPTION = "GitHub Actions - Private Repos Usage"
    PACKAGES_DATA_TRANSFER_USAGE_DESCRIPTION = "GitHub Package Registry - Data Transfer"
    SHARED_STORAGE_USAGE_DESCRIPTION = "GitHub Shared Storage - GitHub.Shared Storage"
    CODESPACES_STORAGE_DESCRIPTION = "GitHub Codespaces - Storage Usage"

    # Deprecated compute description. To be removed when the Meuse integration is finished
    CODESPACES_COMPUTE_DESCRIPTION = "GitHub Codespaces - Compute Usage"

    CODESPACES_COMPUTE_D2_DESCRIPTION = "GitHub Codespaces - Compute D2 Usage"
    CODESPACES_COMPUTE_D4_DESCRIPTION = "GitHub Codespaces - Compute D4 Usage"
    CODESPACES_COMPUTE_D8_DESCRIPTION = "GitHub Codespaces - Compute D8 Usage"
    CODESPACES_COMPUTE_D16_DESCRIPTION = "GitHub Codespaces - Compute D16 Usage"
    CODESPACES_COMPUTE_D32_DESCRIPTION = "GitHub Codespaces - Compute D32 Usage"

    ACTIONS_4_CORE_DESCRIPTION = "GitHub Actions - 4 Core Usage"
    ACTIONS_8_CORE_DESCRIPTION = "GitHub Actions - 8 Core Usage"
    ACTIONS_16_CORE_DESCRIPTION = "GitHub Actions - 16 Core Usage"
    ACTIONS_32_CORE_DESCRIPTION = "GitHub Actions - 32 Core Usage"
    ACTIONS_64_CORE_DESCRIPTION = "GitHub Actions - 64 Core Usage"

    ACTIONS_MACOS_12_CORE_DESCRIPTION = "GitHub Actions - macOS 12-Core Usage"
    ACTIONS_MACOS_8_CORE_DESCRIPTION = "GitHub Actions - macOS 8-Core Usage"
    ACTIONS_MACOS_LARGE_DESCRIPTION = "GitHub Actions - macOS Large Usage"
    ACTIONS_MACOS_XLARGE_DESCRIPTION = "GitHub Actions - macOS XLarge Usage"

    ACTIONS_LINUX_4_CORE_GPU_DESCRIPTION = "GitHub Actions - Linux 4 Core GPU Usage"
    ACTIONS_WINDOWS_4_CORE_GPU_DESCRIPTION = "GitHub Actions - Windows 4 Core GPU Usage"

    ACTIONS_LINUX_2_CORE_ARM_DESCRIPTION = "GitHub Actions - Linux 2 Core ARM Usage"
    ACTIONS_LINUX_4_CORE_ARM_DESCRIPTION = "GitHub Actions - Linux 4 Core ARM Usage"
    ACTIONS_LINUX_8_CORE_ARM_DESCRIPTION = "GitHub Actions - Linux 8 Core ARM Usage"
    ACTIONS_LINUX_16_CORE_ARM_DESCRIPTION = "GitHub Actions - Linux 16 Core ARM Usage"
    ACTIONS_LINUX_32_CORE_ARM_DESCRIPTION = "GitHub Actions - Linux 32 Core ARM Usage"
    ACTIONS_LINUX_64_CORE_ARM_DESCRIPTION = "GitHub Actions - Linux 64 Core ARM Usage"

    ACTIONS_WINDOWS_2_CORE_ARM_DESCRIPTION = "GitHub Actions - Windows 2 Core ARM Usage"
    ACTIONS_WINDOWS_4_CORE_ARM_DESCRIPTION = "GitHub Actions - Windows 4 Core ARM Usage"
    ACTIONS_WINDOWS_8_CORE_ARM_DESCRIPTION = "GitHub Actions - Windows 8 Core ARM Usage"
    ACTIONS_WINDOWS_16_CORE_ARM_DESCRIPTION = "GitHub Actions - Windows 16 Core ARM Usage"
    ACTIONS_WINDOWS_32_CORE_ARM_DESCRIPTION = "GitHub Actions - Windows 32 Core ARM Usage"
    ACTIONS_WINDOWS_64_CORE_ARM_DESCRIPTION = "GitHub Actions - Windows 64 Core ARM Usage"

    ACTIONS_LINUX_2_CORE_ADVANCED_DESCRIPTION = "GitHub Actions - Linux 2 Core Advanced Usage"
    ACTIONS_WINDOWS_2_CORE_ADVANCED_DESCRIPTION = "GitHub Actions - Windows 2 Core Advanced Usage"

    CODESPACES_COMPUTE_DESCRIPTIONS = T.let([
      CODESPACES_COMPUTE_DESCRIPTION,
      CODESPACES_COMPUTE_D2_DESCRIPTION,
      CODESPACES_COMPUTE_D4_DESCRIPTION,
      CODESPACES_COMPUTE_D8_DESCRIPTION,
      CODESPACES_COMPUTE_D16_DESCRIPTION,
      CODESPACES_COMPUTE_D32_DESCRIPTION,
    ].freeze, T::Array[String])

    ACTIONS_RUNNERS_DESCRIPTIONS = T.let([
      ACTIONS_16_CORE_DESCRIPTION,
      ACTIONS_32_CORE_DESCRIPTION,
      ACTIONS_4_CORE_DESCRIPTION,
      ACTIONS_64_CORE_DESCRIPTION,
      ACTIONS_8_CORE_DESCRIPTION,
      ACTIONS_LINUX_16_CORE_ARM_DESCRIPTION,
      ACTIONS_LINUX_2_CORE_ADVANCED_DESCRIPTION,
      ACTIONS_LINUX_2_CORE_ARM_DESCRIPTION,
      ACTIONS_LINUX_32_CORE_ARM_DESCRIPTION,
      ACTIONS_LINUX_4_CORE_ARM_DESCRIPTION,
      ACTIONS_LINUX_4_CORE_GPU_DESCRIPTION,
      ACTIONS_LINUX_64_CORE_ARM_DESCRIPTION,
      ACTIONS_LINUX_8_CORE_ARM_DESCRIPTION,
      ACTIONS_MACOS_12_CORE_DESCRIPTION,
      ACTIONS_MACOS_8_CORE_DESCRIPTION,
      ACTIONS_MACOS_LARGE_DESCRIPTION,
      ACTIONS_MACOS_XLARGE_DESCRIPTION,
      ACTIONS_WINDOWS_16_CORE_ARM_DESCRIPTION,
      ACTIONS_WINDOWS_2_CORE_ADVANCED_DESCRIPTION,
      ACTIONS_WINDOWS_2_CORE_ARM_DESCRIPTION,
      ACTIONS_WINDOWS_32_CORE_ARM_DESCRIPTION,
      ACTIONS_WINDOWS_4_CORE_ARM_DESCRIPTION,
      ACTIONS_WINDOWS_4_CORE_GPU_DESCRIPTION,
      ACTIONS_WINDOWS_64_CORE_ARM_DESCRIPTION,
      ACTIONS_WINDOWS_8_CORE_ARM_DESCRIPTION,
    ].freeze, T::Array[String])

    COPILOT_FOR_BUSINESS_USAGE_DESCRIPTION = "GitHub Copilot"
    COPILOT_ENTERPRISE_USAGE_DESCRIPTION = "GitHub Copilot Enterprise"
    COPILOT_STANDALONE_USAGE_DESCRIPTION = "GitHub Copilot Standalone"

    COPILOT_DESCRIPTIONS = T.let([
      COPILOT_FOR_BUSINESS_USAGE_DESCRIPTION,
      COPILOT_ENTERPRISE_USAGE_DESCRIPTION,
      COPILOT_STANDALONE_USAGE_DESCRIPTION
    ].freeze, T::Array[String])

    USAGE_DESCRIPTIONS = T.let([
      ACTIONS_PRIVATE_USAGE_DESCRIPTION,
      PACKAGES_DATA_TRANSFER_USAGE_DESCRIPTION,
      SHARED_STORAGE_USAGE_DESCRIPTION,
      CODESPACES_STORAGE_DESCRIPTION,
    ].concat(CODESPACES_COMPUTE_DESCRIPTIONS).concat(ACTIONS_RUNNERS_DESCRIPTIONS).concat(COPILOT_DESCRIPTIONS).freeze, T::Array[String])

    MANAGING_ENTITY_ID_KEY = "managing_entity_id"

    enum :subscribable_type, {
      Marketplace::ListingPlan.name => 0,
      SponsorsTier.name => 1,
      Billing::ProductUUID.name => 2,
    }, prefix: :subscribable

    enum :listing_type, {
      Marketplace::Listing.name => 0,
      SponsorsListing.name => 1,
    }, prefix: :listing

    belongs_to :billing_transaction, inverse_of: :line_items
    belongs_to :listing, polymorphic: true
    belongs_to :subscribable, polymorphic: true
    belongs_to :marketplace_listing_plan,
               class_name: "Marketplace::ListingPlan",
               foreign_key: :subscribable_id,
               inverse_of: :billing_transaction_line_items
    belongs_to :product_uuid,
               foreign_key: :subscribable_id,
               inverse_of: :billing_transaction_line_items
    belongs_to :sponsors_tier,
               foreign_key: :subscribable_id,
               inverse_of: :billing_transaction_line_items

    has_many :tax_items,
      dependent: :destroy,
      class_name: "Billing::BillingTransaction::TaxItem",
      inverse_of: :line_item

    has_one :plan_subscription, through: :billing_transaction
    has_one :user, through: :billing_transaction, source: :live_user

    validates :billing_transaction, presence: true
    validates :description, presence: true, unicode3: true
    validates :quantity, presence: true, numericality: true
    validates :amount_in_cents, presence: true, numericality: true
    validate :billing_transaction_payment_type_supports_subscribable_type, on: :create
    validate :subscribable_is_for_listing
    validate :subscribable_type_matches_listing_type
    validate :listing_set_if_subscribable_set

    scope :marketplace, -> { where(subscribable_type: Marketplace::ListingPlan.name) }
    scope :product_uuids, -> { where(subscribable_type: Billing::ProductUUID.name) }
    scope :copilot, -> { joins(:product_uuid).product_uuids.where(product_uuids: { product_type: "github.copilot" }) }
    scope :advanced_security, -> { joins(:product_uuid).product_uuids.where(product_uuids: { product_type: "github.advanced_security" }) }
    scope :github, -> { where(subscribable_id: nil) }
    scope :subscribable, -> { where.not(subscribable_id: nil) }
    scope :paid, -> { where.not(amount_in_cents: 0) }
    scope :successful, -> { joins(:billing_transaction).merge(Billing::BillingTransaction.successful) }

    scope :for_user, -> (user_id) do
      joins(:billing_transaction).merge(Billing::BillingTransaction.for_user(user_id))
    end

    scope :for_business, -> (business) do
      joins(:billing_transaction).merge(Billing::BillingTransaction.for_business(business))
    end

    scope :for_subscribable, ->(subscribable_or_id) { where(subscribable: subscribable_or_id) }

    scope :for_subscribable_id_and_amount_in_cents, ->(subscribable_id, amount_in_cents) do
      where(subscribable_id: subscribable_id, amount_in_cents: amount_in_cents)
    end

    # Public: Filter line items by the given subscribable ID and user ID to include only those
    # for the specified subscribable where the line item's billing transaction is for the specified
    # user.
    #
    # subscribable_id - Integer ID, e.g., for a SponsorsTier; you'll want to also filter the
    #                   resulting relation by the appropriate subscribable_type
    # user_id - Integer User or Organization ID
    #
    # Returns an ActiveRecord::Relation of Billing::BillingTransaction::LineItem.
    scope :for_subscribable_and_user, ->(subscribable_id, user_id) do
      for_subscribable(subscribable_id).for_user(user_id)
    end

    # Public: Returns LineItems tied via the Billing::BillingTransaction to a given plan subscription
    scope :for_sponsors_plan_subscription, ->(sponsors_plan_subscription_id) do
      joins(:billing_transaction)
        .merge(Billing::BillingTransaction.for_sponsors_plan_subscription(sponsors_plan_subscription_id))
    end

    scope :usage, -> { where(description: USAGE_DESCRIPTIONS) }
    scope :actions_usage, -> { where(description: [ACTIONS_PRIVATE_USAGE_DESCRIPTION].concat(ACTIONS_RUNNERS_DESCRIPTIONS)) }
    scope :packages_data_transfer_usage, -> { where(description: PACKAGES_DATA_TRANSFER_USAGE_DESCRIPTION) }
    scope :shared_storage_usage, -> { where(description: SHARED_STORAGE_USAGE_DESCRIPTION) }
    scope :codespaces_storage_usage, -> { where(description: CODESPACES_STORAGE_DESCRIPTION) }
    scope :codespaces_compute_usage, -> { where(description: CODESPACES_COMPUTE_DESCRIPTIONS) }
    scope :codespaces_usage, -> { where(description: [CODESPACES_STORAGE_DESCRIPTION].concat(CODESPACES_COMPUTE_DESCRIPTIONS)) }
    scope :copilot_for_business_usage, -> { where(description: COPILOT_FOR_BUSINESS_USAGE_DESCRIPTION, subscribable: nil) } # Copilot Business is not tied to a subscribable
    # The subscribable is nil for metered copilot. This distinguishes it from copilot for individuals
    scope :metered_copilot_usage, -> { where(description: COPILOT_DESCRIPTIONS, subscribable: nil) }

    scope :before_line_item, ->(line_item_or_id) { where("#{table_name}.id < ?", line_item_or_id) }
    scope :created_between, ->(start_date, end_date) { where(created_at: start_date..end_date) }
    scope :created_during, ->(time_range) { where(created_at: time_range) }
    scope :created_at_or_after, ->(time) { created_during(time..) }
    scope :transaction_created_at_or_after, ->(timestamp) do
      joins(:billing_transaction).merge(Billing::BillingTransaction.created_at_or_after(timestamp))
    end
    scope :transaction_created_before, ->(timestamp) do
      joins(:billing_transaction).merge(Billing::BillingTransaction.created_before(timestamp))
    end
    scope :newest_first, -> { order(created_at: :desc) }
    scope :active_service_period, -> { where("service_start_date <= :date and service_end_date >= :date", date: GitHub::Billing.today) }

    sig { returns(Billing::Money) }
    def total_amount
      to_money + tax_amount
    end

    sig { returns(Billing::Money) }
    def tax_amount
      Billing::Money.new(tax_items.sum(&:amount_in_cents))
    end

    sig { params(tax_item: Billing::Zuora::TaxationItem).returns(Billing::BillingTransaction::TaxItem) }
    def create_tax_item_from_source(tax_item)
      tax_items.create(
        amount_in_cents: tax_item.tax_amount.cents,
        exempt_amount_in_cents: tax_item.exempt_amount.cents,
        country: tax_item.country,
        name: tax_item.name,
        jurisdiction: tax_item.jurisdiction,
        location_code: tax_item.location_code,
        tax_code: tax_item.tax_code,
        tax_code_description: tax_item.tax_code_description,
        tax_date: tax_item.tax_date,
        tax_rate: tax_item.tax_rate,
        tax_rate_description: tax_item.tax_rate_description,
        tax_rate_type: tax_item.tax_rate_type,
        source_id: tax_item.id,
        source_name: tax_item.source_name,
      )
    rescue ActiveRecord::RecordNotUnique
      # This is more of a just in case scenario and we want to log in case we hit it
      GitHub.logger.warn(
        "Tax item already exists",
        "code.function": "create_tax_item_from_source",
        "gh.billing.billing_transaction.tax_item.source_id": tax_item.id,
        "gh.billing.billing_transaction.tax_item.source_name": tax_item.source_name,
      )

      # If the tax item already exists, return it instead of failing
      # There's still a chance that a record could be deleted somehow but that's a far off edge case
      # and we have logs above to debug if necessary
      T.must(tax_items.find_by(source_id: tax_item.id, source_name: tax_item.source_name))
    end

    # Public: Get our best guess at the plan subscription used for this line item. Will either be the
    # plan subscription explicitly recorded on the billing transaction, or the transaction's user's current
    # general-purpose plan subscription.
    #
    # Returns a Billing::PlanSubscription or nil.
    sig { returns(T.nilable(Billing::PlanSubscription)) }
    def plan_subscription
      # Safe to fall back to the general-purpose plan subscription on the user if one was not recorded explicitly on
      # this line item's transaction, because by the time we introduced the concept of plan subscriptions
      # with a different `purpose`, we were consistently specifying `plan_subscription_id` on billing transactions:
      super || user&.plan_subscription
    end

    sig { returns(T.nilable(Integer)) }
    def billing_transaction_user_id
      billing_transaction&.user_id
    end

    sig { returns(T.nilable(String)) }
    def transaction_id
      billing_transaction&.transaction_id
    end

    sig { params(user_id: T.nilable(Integer)).returns(T::Boolean) }
    def billing_transaction_for_user?(user_id)
      billing_transaction_user_id == user_id
    end

    sig { returns(T.nilable(String)) }
    def billing_country
      billing_transaction&.country
    end

    sig { returns(T.nilable(String)) }
    def billing_region
      billing_transaction&.region
    end

    sig { returns(T.nilable(String)) }
    def last_billing_status
      billing_transaction&.last_status
    end

    sig { returns(T.nilable(String)) }
    def subscribable_name
      subscribable&.name
    end

    sig { returns(T::Boolean) }
    def service_period?
      service_start_date.present? && service_end_date.present?
    end

    sig { params(format: String, separator: String).returns(T.nilable(String)) }
    def formatted_service_period(format: "%Y-%m-%d", separator: "to")
      service_start_date = self.service_start_date
      service_end_date = self.service_end_date
      return if service_start_date.blank? || service_end_date.blank?

      service_start_date.strftime(format) + " #{separator} " + service_end_date.strftime(format)
    end

    # Public: Get a monetary representation of the subscribable for this line item.
    sig { returns(T.nilable(Billing::Money)) }
    def subscribable_money
      subscribable&.to_money
    end

    sig { returns(T::Boolean) }
    def paid?
      !amount_in_cents.zero?
    end

    sig { returns(T::Boolean) }
    def subscribable?
      subscribable_id.present?
    end

    sig { returns(T::Boolean) }
    def marketplace?
      subscribable_type == Marketplace::ListingPlan.name
    end

    sig { returns(T::Boolean) }
    def sponsorship?
      subscribable_type == SponsorsTier.name
    end

    sig { returns(T::Boolean) }
    def product_uuid?
      subscribable_type == Billing::ProductUUID.name
    end

    sig { returns(T::Boolean) }
    def copilot?
      product_uuid? && subscribable&.product_type == "github.copilot"
    end

    sig { returns(T::Boolean) }
    def advanced_security?
      product_uuid? && subscribable&.product_type == "github.advanced_security"
    end

    sig { returns(T::Boolean) }
    def usage_charge?
      Billing::BillingTransaction::LineItem::USAGE_DESCRIPTIONS.include?(description)
    end

    sig { returns(T::Boolean) }
    def prorated_charge?
      !!billing_transaction&.prorated_charge?
    end

    sig { returns(T::Boolean) }
    def stripe_transfers_enabled?
      return false unless subscribable.respond_to?(:stripe_transfers_enabled?)
      subscribable.stripe_transfers_enabled?
    end

    sig { returns(Billing::Money) }
    def to_money
      Billing::Money.new(amount_in_cents)
    end

    sig { returns(T::Boolean) }
    def one_time?
      return false unless subscribable.respond_to?(:one_time?)
      subscribable.one_time?
    end

    sig { returns(T::Boolean) }
    def recurring?
      return false unless subscribable.respond_to?(:recurring?)
      subscribable.recurring?
    end

    sig { returns(T.nilable(String)) }
    def core_count_from_description
      if linux_gpu_core = (description[/Linux ([0-9]+) Core GPU[\s-]/, 1])
        return "Ubuntu GPU #{linux_gpu_core} core"
      end

      if windows_gpu_core = (description[/Windows ([0-9]+) Core GPU[\s-]/, 1])
        return "Windows GPU #{windows_gpu_core} core"
      end

      if linux_arm_core = (description[/Linux ([0-9]+) Core ARM[\s-]/, 1])
        return "Ubuntu ARM #{linux_arm_core} core"
      end

      if windows_arm_core = (description[/Windows ([0-9]+) Core ARM[\s-]/, 1])
        return "Windows ARM #{windows_arm_core} core"
      end

      if linux_advanced_core = (description[/Linux ([0-9]+) Core Advanced[\s-]/, 1])
        return "Ubuntu Advanced #{linux_advanced_core} core"
      end

      if windows_advanced_core = (description[/Windows ([0-9]+) Core Advanced[\s-]/, 1])
        return "Windows Advanced #{windows_advanced_core} core"
      end

      # Example: "GitHub Codespaces - Compute D8 Usage"
      # Result: 8 core
      if core = (description[/([0-9]+)[\s-]/, 1])
        return "#{core} core"
      end
      # Example: "GitHub Actions - macOS Large Usage"
      # Result: macOS Large
      description[/(macOS Large|macOS XLarge)/, 1]
    end

    sig { returns(String) }
    def copilot_sku_description
      case description
      when /\AGitHub Copilot Enterprise\z/
        "Enterprise"
      when /\AGitHub Copilot\z/, /\AGitHub Copilot Standalone\z/
        "Business"
      else
        "Unknown"
      end
    end

    # Public: Get a line of text to describe this line item in a receipt.
    sig { returns(String) }
    def receipt_text
      if description_includes_amount?
        description_without_sponsors_prefix # e.g., "maintainerName - $18 a month - fee"
      else
        "#{description_without_sponsors_prefix} (#{to_money.format})" # e.g., "maintainerName - $18 a month - fee ($1.08)"
      end
    end

    private

    # Private: Get the item description, without the "sponsors-" prefix if it has one.
    # e.g. a description of "sponsors-maintainerName - $18 a month" will return "maintainerName - $18 a month"
    sig { returns(String) }
    def description_without_sponsors_prefix
      description.delete_prefix(SponsorsListing::SLUG_PREFIX)
    end

    # Private: Does the description include the dollar amount in some human-readable format?
    sig { returns(T::Boolean) }
    def description_includes_amount?
      amount = to_money
      formatted_amount = amount.format # e.g., "$5.00"
      alternate_formatted_amount = amount.format(no_cents_if_whole: true) # e.g., "$5"
      words = description.split(/\s+/) # e.g., ["sponsors-maintainerName", "-", "$18", "a", "month"]
      words.include?(formatted_amount) || words.include?(alternate_formatted_amount)
    end

    sig { void }
    def subscribable_type_matches_listing_type
      return unless subscribable_type && listing_type

      if subscribable_type == "SponsorsTier" && listing_type != "SponsorsListing"
        errors.add(:listing_type, "does not match subscribable type for Sponsors")
      elsif subscribable_type == "Marketplace::ListingPlan" && listing_type != "Marketplace::Listing"
        errors.add(:listing_type, "does not match subscribable type for Marketplace")
      end
    end

    sig { void }
    def billing_transaction_payment_type_supports_subscribable_type
      billing_transaction = self.billing_transaction
      return unless billing_transaction && subscribable_type

      if subscribable_SponsorsTier? && billing_transaction.paypal?
        errors.add(:subscribable_type, "cannot be paid for using PayPal")
      end
    end

    sig { void }
    def listing_set_if_subscribable_set
      return if subscribable_Billing_ProductUUID?
      if subscribable && !listing
        errors.add(:listing_id, "is required when there's a subscribable")
      elsif listing && !subscribable
        errors.add(:subscribable_id, "is required when there's a listing")
      end
    end

    sig { void }
    def subscribable_is_for_listing
      return unless subscribable && listing

      unless subscribable.listing == listing
        errors.add(:subscribable_id, "is for a different listing")
      end
    end
  end
end
