# typed: true
# frozen_string_literal: true

module Billing
  class BillingPlatformOnboardingCohort
    T::Sig

    sig { returns(T::Array[Billing::BillingPlatformOnboardingCohort]) }
    def self.all
      results = {}

      billing_platform_enabled_product_customers = if FeatureFlag.vexi.enabled_or_raise?(:billing_platform_exclude_deleted_businesses_from_cohorts_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        BillingPlatformEnabledProduct.with_eligible_customer.in_a_cohort
      else
        BillingPlatformEnabledProduct.in_a_cohort
      end

      # Get processed count for each cohort
      billing_platform_enabled_product_customers.migrated.group(:cohort_name).count.each do |cohort_name, count|
        results[cohort_name] ||= {}
        results[cohort_name][:processed_count] = count
      end

      # Get unprocessed count for each cohort
      billing_platform_enabled_product_customers.not_migrated.not_failed.group(:cohort_name).count.each do |cohort_name, count|
        results[cohort_name] ||= {}
        results[cohort_name][:not_processed_count] = count
      end

      # Get failed count for each cohort
      billing_platform_enabled_product_customers.not_migrated.failed.group(:cohort_name).count.each do |cohort_name, count|
        results[cohort_name] ||= {}
        results[cohort_name][:failed_count] = count
      end

      results.map do |cohort_name, data|
        Billing::BillingPlatformOnboardingCohort.new(
          cohort_name:,
          processed_count: data[:processed_count],
          not_processed_count: data[:not_processed_count],
          failed_count: data[:failed_count],
        )
      end
    end

    sig { returns(String) }
    attr_reader :cohort_name

    sig { returns(Integer) }
    attr_reader :processed_count

    sig { returns(Integer) }
    attr_reader :not_processed_count

    sig { returns(Integer) }
    attr_reader :failed_count

    sig { params(cohort_name: String, processed_count: T.nilable(Integer), not_processed_count: T.nilable(Integer), failed_count: T.nilable(Integer)).void }
    def initialize(cohort_name:, processed_count:, not_processed_count:, failed_count:)
      @cohort_name = cohort_name
      @processed_count = T.must(processed_count || 0)
      @not_processed_count = T.must(not_processed_count || 0)
      @failed_count = T.must(failed_count || 0)
    end

    sig { params(cohort_name: String).returns(ActiveRecord::Relation) }
    def self.customers(cohort_name:)
      BillingPlatformEnabledProduct
        .joins(:customer)
        .where(cohort_name: cohort_name)
        .select(
          "customers.id",
          "customers.name",
          "billing_platform_enabled_products.migration_date"
        )
        .distinct
        .order("customers.name ASC")
    end
  end
end
