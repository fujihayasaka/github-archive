# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingPlatformOnboardingCohortTest < GitHub::TestCase
  setup do
    enable_feature_flag(:billing_platform_exclude_deleted_businesses_from_cohorts_enabled)
  end

  test ".all returns a list of cohorts with the processed/unprocessed stats generated" do
    cohort_1 = "Onboarding Cohort 1"
    cohort_2 = "Onboarding Cohort 2"

    business1 = create(:business)

    # Create 4 unprocessed products with unique customers
    4.times do
      customer = create(:customer, business: business1)
      create(:billing_platform_enabled_product,
        cohort_name: cohort_1,
        migration_date: nil,
        customer: customer
      )
    end

    # Create 2 failed products with unique customers
    2.times do
      customer = create(:customer, business: business1)
      create(:billing_platform_enabled_product,
        cohort_name: cohort_1,
        failed_at: Time.zone.now,
        customer: customer
      )
    end

    # Create 6 processed products with unique customers
    6.times do
      customer = create(:customer, business: business1)
      create(:billing_platform_enabled_product,
        cohort_name: cohort_1,
        migration_date: 1.day.ago.to_date,
        customer: customer
      )
    end

    # Create 10 unprocessed products for cohort 2
    business2 = create(:business)
    10.times do
      customer = create(:customer, business: business2)
      create(:billing_platform_enabled_product,
        cohort_name: cohort_2,
        migration_date: nil,
        customer: customer
      )
    end

    cohorts = Billing::BillingPlatformOnboardingCohort.all

    assert_equal 2, cohorts.count

    first_cohort = T.must(cohorts.find { |cohort| cohort.cohort_name == cohort_1 })

    assert_equal 6, first_cohort.processed_count
    assert_equal 4, first_cohort.not_processed_count
    assert_equal 2, first_cohort.failed_count

    second_cohort = T.must(cohorts.find { |cohort| cohort.cohort_name == cohort_2 })
    assert_equal 0, second_cohort.processed_count
    assert_equal 10, second_cohort.not_processed_count
    assert_equal 0, second_cohort.failed_count
  end

  test ".all excludes deleted businesses from cohort counts" do
    cohort_name = "Onboarding Cohort 1"

    # Create active businesses/products
    FactoryBot.create_list(:billing_platform_enabled_product, 2, cohort_name: cohort_name, migration_date: nil)

    # Create deleted business and product
    deleted_business = FactoryBot.create(:business, deleted_at: 1.day.ago)
    deleted_customer = FactoryBot.create(:customer, business: deleted_business)
    FactoryBot.create(:billing_platform_enabled_product,
      customer: deleted_customer,
      cohort_name: cohort_name,
      migration_date: nil
    )

    cohorts = Billing::BillingPlatformOnboardingCohort.all
    cohort = T.must(cohorts.find { |c| c.cohort_name == cohort_name })

    # Should only count the 2 active businesses
    assert_equal 2, cohort.not_processed_count
    assert_equal 0, cohort.processed_count
  end
end if GitHub.billing_enabled?
