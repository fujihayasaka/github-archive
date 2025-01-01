# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::SharedStorageUsageTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  fixtures do
    @metered_billing_cycle_starts_at = GitHub::Billing.timezone.local(2019, 10, 1, 0, 0).freeze
    @start_of_third_billing_day = (@metered_billing_cycle_starts_at + 2.days).freeze

    @user = create(:user)
    @user_repository = create(:repository, owner: @user)

    @business = create(:business)
    @organization1 = create(:organization, business: @business)
    @organization1_repository = create(:repository, owner: @organization1)
    @organization2 = create(:organization, business: @business)
    @organization2_repository = create(:repository, owner: @organization2)
  end

  setup do
    travel_to @start_of_third_billing_day do
      # For User
      # assume 512 MB of usage on the first day (the entilement amount)
      # assume an additional 2GB of usage the second day for a total of 2.5 GB

      # Create a record for "latest_private_billable_stored_megabytes"
      # which represent's dotcom's knowledge of the current storage amount on disk
      create(
        :shared_storage_current_usage,
        :private_visibility,
        owner: @user,
        billable_owner: @user,
        repository: @user_repository,
        aggregate_size_in_bytes: 2.gigabytes + 512.megabytes,
        effective_at: @start_of_third_billing_day,
      )

      # For Business
      # Day 1
      # Assume 25GB of storage on the first day for org1
      # Assume 25GB of storage on the first day for org2
      # (this is the total entitlment)

      # Day 2
      # Org 1 has uses the orginal 25GB, plus another 2GB of storage
      # Org 2 still has the original 25GB

      # Create a record for "latest_private_billable_stored_megabytes" for org1
      # which represent's dotcom's knowledge of the current storage amount on disk
      create(
        :shared_storage_current_usage,
        :private_visibility,
        owner: @organization1,
        billable_owner: @business,
        repository: @organization1_repository,
        aggregate_size_in_bytes: 25.gigabytes + 2.gigabytes,
        effective_at: @start_of_third_billing_day,
      )

      # Create a record for "latest_private_billable_stored_megabytes" for org2
      # which represent's dotcom's knowledge of the current storage amount on disk
      create(
        :shared_storage_current_usage,
        :private_visibility,
        owner: @organization2,
        billable_owner: @business,
        repository: @organization2_repository,
        aggregate_size_in_bytes: 25.gigabytes,
        effective_at: @start_of_third_billing_day,
      )
    end

    @user.stubs(:current_metered_billing_cycle_starts_at).returns(@metered_billing_cycle_starts_at)
    @business.stubs(:current_metered_billing_cycle_starts_at).returns(@metered_billing_cycle_starts_at)
  end

  context "using 'usage_quote'" do
    context "#has_error?" do
      test "returns false on successful api call" do
        mock_calculate_usage_quotes_response(
          product_name: "shared_storage",
          product_sku_name: "default",
          total_proposed_usage_effective_quantity: 72.gigabytes
        )
        refute Billing::SharedStorageUsage.usage_quote(@user).has_error?
      end

      test "returns true on successful failed call" do
        mock_calculate_usage_quotes_response_error
        assert Billing::SharedStorageUsage.usage_quote(@user).has_error?
      end
    end

    context "#private_megabyte_hours_used" do
      test "returns the total_historical_usage coverted to megabytes for the user from the billing-api" do
        travel_to @start_of_third_billing_day do
          mock_calculate_usage_quotes_response(
            product_name: "shared_storage",
            product_sku_name: "default",
            total_proposed_usage_effective_quantity: 72.gigabytes
          )
          assert_equal 73728, Billing::SharedStorageUsage.usage_quote(@user).private_megabyte_hours_used
        end
      end

      test "returns the total_historical_usage coverted to megabytes for the business from the billing-api" do
        travel_to @start_of_third_billing_day do
          mock_calculate_usage_quotes_response(
            product_name: "shared_storage",
            product_sku_name: "default",
            total_proposed_usage_effective_quantity: 2448.gigabytes
          )
          assert_equal 2506752, Billing::SharedStorageUsage.usage_quote(@business).private_megabyte_hours_used
        end
      end

      test "returns nil on api error" do
        mock_calculate_usage_quotes_response_error
        assert_nil Billing::SharedStorageUsage.usage_quote(@user).private_megabyte_hours_used
      end
    end

    context "#estimated_monthly_paid_megabytes" do
      test "returns the estimated number of private megabyte hours the user will use" do
        travel_to @start_of_third_billing_day do
          # day 1 0.5GB * 24 hours
          # day 2 2.5GB * 24 hours
          # = 72 GB-Hours of historical usage
          mock_calculate_usage_quotes_response(
            product_name: "shared_storage",
            product_sku_name: "default",
            total_proposed_usage_effective_quantity: 72.gigabytes
          )

          # 72 GB-Hours of historical usage
          # + 2.5GB * 24 hours * 29 days (1740.0 GB-Hours)
          # = 1812 GB-Hours = 2493 MB-Months
          # 2493 MB-Months - 512 MB (included amount for the free plan) = 1981 MB-Months
          assert_equal 1981, Billing::SharedStorageUsage.usage_quote(@user).estimated_monthly_paid_megabytes
        end
      end

      test "returns number of private megabyte hours used for business" do
        travel_to @start_of_third_billing_day do
          # organization1: (24 hours * 25GB) + (24 hours * (25GB + 2GB) = 1248 GB-hours = 1277952 MBhour
          # organization2: (48 hours * 25GB) = 1200 GB-hours = 1228800 MB-hours
          # total: 2448GBh = 2506752 MBh historical usage
          mock_calculate_usage_quotes_response(
            product_name: "shared_storage",
            product_sku_name: "default",
            total_proposed_usage_effective_quantity: 2448.gigabytes
          )

          # 2448 GB-Hours of historical usage
          # + 52GB * 24 hours * 29 days (36192.0 GB-Hours)
          # = 38640 GB-Hours = 53181 MB-Months
          # 53181 MB-Months - 51200 MB (included amount for the enterprise plan) = 1981 MB-Months
          assert_equal 1981, Billing::SharedStorageUsage.usage_quote(@business).estimated_monthly_paid_megabytes
        end
      end

      test "returns nil on api error" do
        mock_calculate_usage_quotes_response_error
        assert_nil Billing::SharedStorageUsage.usage_quote(@user).estimated_monthly_paid_megabytes
      end
    end

    context "#paid_usage_percentage" do
      test "returns percent of usage is paid" do
        travel_to @start_of_third_billing_day do
          mock_calculate_usage_quotes_response(
            product_name: "shared_storage",
            product_sku_name: "default",
            total_proposed_usage_effective_quantity: 2448.gigabytes
          )
          # estimated paid usage: 2.gigabytes * (30 days (only entitlment usage the first day) * 24 hours) = 1.935483871GB-months
          # included in plan: 50GB
          # (1.935483871GB / 50GB) * 100 = 3.870967742% = 3% when rounded down
          assert_equal 3, Billing::SharedStorageUsage.usage_quote(@business).paid_usage_percentage
        end
      end

      test "returns nil on api error" do
        mock_calculate_usage_quotes_response_error
        assert_nil Billing::SharedStorageUsage.usage_quote(@user).paid_usage_percentage
      end
    end

    context "#included_usage_percentage" do
      test "returns percent of included usage that's been consumed" do
        travel_to @start_of_third_billing_day do
          user = create(:user)

          # Use 256MB (50% of the included amount for the plan) for the whole period

          # Create a record for "latest_private_billable_stored_megabytes"
          # which represents dotcom's knowledge of the current storage amount on disk
          create(
            :shared_storage_current_usage,
            :private_visibility,
            owner: user,
            billable_owner: user,
            repository_id: 0,
            aggregate_size_in_bytes: 256.megabytes,
            effective_at: @start_of_third_billing_day,
          )
          # 2 days of historical usage at 256 MB
          mock_calculate_usage_quotes_response(
            product_name: "shared_storage",
            product_sku_name: "default",
            total_proposed_usage_effective_quantity: 256.megabytes * 2 * 24
          )
          usage = Billing::SharedStorageUsage.usage_quote(user)

          assert_equal 50, usage.included_usage_percentage
        end
      end

      test "returns 100 percent if maxed out" do
        travel_to @start_of_third_billing_day do
          mock_calculate_usage_quotes_response(
            product_name: "shared_storage",
            product_sku_name: "default",
            total_proposed_usage_effective_quantity: 72.gigabytes
          )
          assert_equal 100, Billing::SharedStorageUsage.usage_quote(@user).included_usage_percentage
        end
      end
    end
  end

  context "using '.product_usage'" do
    context "#has_error?" do
      test "returns false on successful api call" do
        mock_list_product_usage_response(product: "shared_storage", sku_name: "default", unit_of_measure: "Megabytes", quantity: 72.gigabytes)
        refute Billing::SharedStorageUsage.product_usage(@user).has_error?
      end

      test "returns true on successful failed call" do
        mock_list_product_usage_response_error
        assert Billing::SharedStorageUsage.product_usage(@user).has_error?
      end
    end

    context "#private_megabyte_hours_used" do
      test "returns the total_historical_usage coverted to megabytes for the user from the billing-api" do
        travel_to @start_of_third_billing_day do
          mock_list_product_usage_response(product: "shared_storage", sku_name: "default", unit_of_measure: "Megabytes", quantity: 72.gigabytes)
          assert_equal 73728, Billing::SharedStorageUsage.product_usage(@user).private_megabyte_hours_used
        end
      end

      test "returns the total_historical_usage coverted to megabytes for the business from the billing-api" do
        travel_to @start_of_third_billing_day do
          mock_list_product_usage_response(product: "shared_storage", sku_name: "default", unit_of_measure: "Megabytes", quantity: 2448.gigabytes)
          assert_equal 2506752, Billing::SharedStorageUsage.product_usage(@business).private_megabyte_hours_used
        end
      end

      test "returns nil on api error" do
        mock_list_product_usage_response_error
        assert_nil Billing::SharedStorageUsage.product_usage(@user).private_megabyte_hours_used
      end
    end

    context "#estimated_monthly_paid_megabytes" do
      test "returns the estimated number of private megabyte hours the user will use" do
        travel_to @start_of_third_billing_day do
          # day 1 0.5GB * 24 hours
          # day 2 2.5GB * 24 hours
          # = 72 GB-Hours of historical usage
          mock_list_product_usage_response(product: "shared_storage", sku_name: "default", unit_of_measure: "Megabytes", quantity: 72.gigabytes)

          # 72 GB-Hours of historical usage
          # + 2.5GB * 24 hours * 29 days (1740.0 GB-Hours)
          # = 1812 GB-Hours = 2493 MB-Months
          # 2493 MB-Months - 512 MB (included amount for the free plan) = 1981 MB-Months
          assert_equal 1981, Billing::SharedStorageUsage.product_usage(@user).estimated_monthly_paid_megabytes
        end
      end

      test "returns number of private megabyte hours used for business" do
        travel_to @start_of_third_billing_day do
          # organization1: (24 hours * 25GB) + (24 hours * (25GB + 2GB) = 1248 GB-hours = 1277952 MBhour
          # organization2: (48 hours * 25GB) = 1200 GB-hours = 1228800 MB-hours
          # total: 2448GBh = 2506752 MBh historical usage
          mock_list_product_usage_response(product: "shared_storage", sku_name: "default", unit_of_measure: "Megabytes", quantity: 2448.gigabytes)

          # 2448 GB-Hours of historical usage
          # + 52GB * 24 hours * 29 days (36192.0 GB-Hours)
          # = 38640 GB-Hours = 53181 MB-Months
          # 53181 MB-Months - 51200 MB (included amount for the enterprise plan) = 1981 MB-Months
          assert_equal 1981, Billing::SharedStorageUsage.product_usage(@business).estimated_monthly_paid_megabytes
        end
      end

      test "returns nil on api error" do
        mock_list_product_usage_response_error
        assert_nil Billing::SharedStorageUsage.product_usage(@user).estimated_monthly_paid_megabytes
      end
    end
  end
end if GitHub.billing_enabled?
