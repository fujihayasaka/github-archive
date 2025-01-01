# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stafftools::MeteredUsageAggregationTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers
  include Billing::ActionsTestHelpers

  setup do
    travel_to(GitHub::Billing.timezone.parse("2019-12-12"))
  end

  teardown do
    travel_back
  end

  context "#upcoming_actions_artifact_storage_expirations" do
    test "returns an array of hashes with information around artifact expiration by repo and date" do
      repository      = create(:repository)
      _not_found_repo = create(:repository)

      tomorrow_event  = create(:shared_storage_artifact_event, :actions_source, :remove_event, repository: repository, effective_at: Time.now + 1.day)
      next_week_event = create(:shared_storage_artifact_event, :actions_source, :remove_event, repository: repository, effective_at: Time.now + 7.days)
      end_times_event = create(:shared_storage_artifact_event, :actions_source, :remove_event, repository: repository, effective_at: Time.now + 89.days)

      _out_of_bounds_event      = create(:shared_storage_artifact_event, :actions_source, :remove_event, repository: repository, effective_at: Time.now - 1.day)
      _not_remove_event         = create(:shared_storage_artifact_event, :actions_source, repository: repository, effective_at: Time.now + 1.week)
      _not_actions_source_event = create(:shared_storage_artifact_event, :remove_event, repository: repository, effective_at: Time.now + 89.days)

      total_expirations_size = ::Billing::SharedStorage::ArtifactEvent.sum(:size_in_bytes)
      expecting_results_size = [tomorrow_event, next_week_event, end_times_event].sum(&:size_in_bytes)
      aggregator             = ::Billing::Stafftools::MeteredUsageAggregation.new(owner_id: repository.owner_id)
      upcoming_expirations   = aggregator.upcoming_actions_artifact_storage_expirations

      # Only one repo has events for this owner
      assert_equal 1, upcoming_expirations.length

      result       = upcoming_expirations.first
      name         = result[:name]
      size_by_date = result[:size_by_date]
      total_size   = result[:total_size]

      assert_equal repository.name, name
      assert_equal 3, size_by_date.length # Three dates
      # Order is not guaranteed in our actual usage of this method, but added a sort to make
      # it a little easier to test, the dates are from the expected events above
      expected_ordered_dates = [::GitHub::Billing.today + 1.day, ::GitHub::Billing.today + 1.week, ::GitHub::Billing.today + 89.days]
      assert_equal expected_ordered_dates, size_by_date.keys.map(&:last).sort
      assert_equal expecting_results_size, total_size
      refute_equal total_expirations_size, expecting_results_size
    end

    test "returns deleted repositories" do
      repository = create(:repository)

      create(:shared_storage_artifact_event, :actions_source, :remove_event, repository: repository, effective_at: Time.now + 1.day)
      create(:shared_storage_artifact_event, :actions_source, :remove_event, repository: repository, effective_at: Time.now + 7.days)
      create(:shared_storage_artifact_event, :actions_source, :remove_event, repository: repository, effective_at: Time.now + 89.days)

      repository.remove(repository.owner, synchronous: true)

      aggregator           = ::Billing::Stafftools::MeteredUsageAggregation.new(owner_id: repository.owner_id)
      upcoming_expirations = aggregator.upcoming_actions_artifact_storage_expirations

      # Only one repo has events for this owner
      assert_equal 1, upcoming_expirations.length

      result = upcoming_expirations.first
      name   = result[:name]

      assert_equal repository.name, name
    end
  end

  context "#shared_storage_usage" do
    test "returns a hash of repository_id keys and the respective aggregate_size_in_bytes for the latest aggregation" do
      aggregate_size = 15.megabytes
      user           = create(:user)
      not_our_owner  = create(:user)
      repo           = create(:repository, from_example: :repository_test_simple)
      usage = create(
        :shared_storage_current_usage,
        :private_visibility,
        owner: user,
        billable_owner: user,
        repository_id: repo.id,
        aggregate_size_in_bytes: aggregate_size,
      )

      # effective_at is set for well before the current metered cycle to ensure it still gets picked up
      add_event = create(:shared_storage_artifact_event,
        :gpr_source,
        :add_event,
        :private_visibility,
        repository: repo,
        effective_at: user.current_metered_billing_cycle_starts_at - 3.months,
        owner: user,
        size_in_bytes: 2.megabytes,
        aggregation_id: usage.id,
      )
      _remove_event = create(
        :shared_storage_artifact_event,
        :gpr_source,
        :remove_event,
        :private_visibility,
        repository: repo,
        effective_at: user.current_metered_billing_cycle_starts_at + 2.days,
        owner: user,
        size_in_bytes: add_event.size_in_bytes - 1.megabyte,
        aggregation_id: usage.id,
      )
      # 14 megabytes is aggregate_size, minus the 1 megabyte used by gpr in the events above
      # effective_at is set for well before the current metered cycle to ensure it still gets picked up
      _actions_add_event = create(
        :shared_storage_artifact_event,
        :actions_source,
        :add_event,
        :private_visibility,
        repository: repo,
        effective_at: user.current_metered_billing_cycle_starts_at - 1.month,
        owner: user,
        size_in_bytes: 14.megabytes,
        aggregation_id: usage.id,
      )

      # None of the following events or aggregations should be included
      _no_aggregation_id_event = create(
        :shared_storage_artifact_event,
        :actions_source,
        :add_event,
        :private_visibility,
        repository: repo,
        effective_at: user.current_metered_billing_cycle_starts_at - 1.month,
        owner: user,
        size_in_bytes: 14.megabytes,
      )

      _different_owner_usage = create(
        :shared_storage_current_usage,
        :private_visibility,
        owner: not_our_owner,
        billable_owner: not_our_owner,
        repository_id: repo.id,
      )

      aggregator = ::Billing::Stafftools::MeteredUsageAggregation.new(owner_id: user.id)
      storage_usage = aggregator.shared_storage_usage

      assert_equal 1, storage_usage.length

      storage_data = storage_usage.first

      assert_equal repo.name, storage_data.repo_name
      assert_equal aggregate_size, storage_data.total_usage_in_bytes
      # We'd expect 28 megabytes if both actions events were picked up, but one does not have an
      # aggregation so its part of the unaggregated usage
      assert_equal 14.megabytes, storage_data.aggregated_actions_usage
      assert_equal 1.megabytes, storage_data.aggregated_gpr_usage
      assert_equal 15.megabytes, storage_data.sum_aggregated_events
      assert_equal 14.megabytes, storage_data.unaggregated_actions_usage
      assert_equal 0.megabytes, storage_data.unaggregated_gpr_usage
    end

    test "returns deleted repositories" do
      aggregate_size = 15.megabytes

      user = create(:user)
      repo = create(:deleted_repository)

      add_event = create(:shared_storage_artifact_event, :gpr_source, :add_event, :private_visibility, repository_id: repo.id, effective_at: user.current_metered_billing_cycle_starts_at + 1.day, owner: user, size_in_bytes: 2.megabytes)
      _actions_add_event = create(:shared_storage_artifact_event, :actions_source, :add_event, :private_visibility, repository_id: repo.id, effective_at: user.current_metered_billing_cycle_starts_at + 1.day, owner: user, size_in_bytes: 2.megabytes)
      _remove_event = create(:shared_storage_artifact_event, :gpr_source, :remove_event, :private_visibility, repository_id: repo.id, effective_at: user.current_metered_billing_cycle_starts_at + 2.days, owner: user, size_in_bytes: add_event.size_in_bytes - 1.megabyte)

      create(:shared_storage_current_usage, :private_visibility, owner: user, billable_owner: user, repository_id: repo.id, aggregate_size_in_bytes: aggregate_size)
      create(:shared_storage_current_usage, :private_visibility, owner: user, billable_owner: user, repository_id: 0)

      aggregator = ::Billing::Stafftools::MeteredUsageAggregation.new(owner_id: user.id)
      storage_usage = aggregator.shared_storage_usage

      assert_equal 2, storage_usage.length

      # NOTE: the factory for shared_storage_current_usage defaults to 10.megabytes
      assert_equal [repo.name, nil], storage_usage.map { |usage| usage.repo_name }
      assert_equal [aggregate_size, 10.megabytes], storage_usage.map { |usage| usage.total_usage_in_bytes }
    end
  end

  context "#packages_bandwidth_since_cycle_reset" do
    test "returns an array of hashes with information around package download bandwidth" do
      user             = create(:user)
      repo             = create(:repository, from_example: :repository_test_simple)
      registry_package = create(:registry_package, repository: repo)

      last_day_date = T.cast(Time.now - 1.day, Time)
      last_week_date = T.cast(Time.now - 1.week, Time)
      byte_size = 1610612736

      usage_line_items = []
      [last_day_date, last_week_date].each do |date|
        usage_line_items << create_mock_usage_line_item(
          usage_at: Google::Protobuf::Timestamp.new(seconds: date.to_i),
          repository_id: repo.id,
          billable_owner_id: user.id,
          quantity: byte_size,
          custom_fields: {
            "package.id": registry_package.id.to_s
          }
        )
      end
      mock_get_usage_line_items_response_with(usage_line_items: usage_line_items)

      expected_results_size = byte_size * 2
      aggregator            = ::Billing::Stafftools::MeteredUsageAggregation.new(owner_id: user.id)
      recent_downloads      = aggregator.packages_bandwidth_since_cycle_reset

      # One one package has downloads
      assert_equal 1, recent_downloads.length
      assert_equal ::GitHub::Billing.today.beginning_of_month, user.current_metered_billing_cycle_starts_at.to_date

      result            = recent_downloads.first
      name              = result[:name]
      bandwidth_by_date = result[:bandwidth_by_date]
      total_bandwidth   = result[:total_bandwidth]

      assert_equal registry_package.name, name
      assert_equal 2, bandwidth_by_date.length # 2 download events
      # Order is not guaranteed in our actual usage of this method, but added a sort to make
      # it a little easier to test, the dates are from the expected data transfers above
      expected_ordered_dates = [::GitHub::Billing.today - 1.week, ::GitHub::Billing.today - 1.day]
      assert_equal expected_ordered_dates, bandwidth_by_date.keys.map(&:last).sort
      assert_equal expected_results_size, total_bandwidth

    end

    test "shows deleted and missing packages" do
      user             = create(:user)
      repo             = create(:repository, from_example: :repository_test_simple)
      registry_package = create(:registry_package, repository: repo)

      last_day_date = T.cast(Time.now - 1.day, Time)
      last_week_date = T.cast(Time.now - 1.week, Time)
      byte_size = 1610612736

      usage_line_items = []
      [last_day_date, last_week_date].each do |date|
        usage_line_items << create_mock_usage_line_item(
          usage_at: Google::Protobuf::Timestamp.new(seconds: date.to_i),
          repository_id: repo.id,
          billable_owner_id: user.id,
          quantity: byte_size,
          custom_fields: {
            "package.id": registry_package.id.to_s
          }
        )
      end
      mock_get_usage_line_items_response_with(usage_line_items: usage_line_items)

      registry_package.delete

      expected_results_size = byte_size * 2
      aggregator            = ::Billing::Stafftools::MeteredUsageAggregation.new(owner_id: user.id)
      recent_downloads      = aggregator.packages_bandwidth_since_cycle_reset

      # One one package has downloads
      assert_equal 1, recent_downloads.length
      assert_equal ::GitHub::Billing.today.beginning_of_month, user.current_metered_billing_cycle_starts_at.to_date

      result            = recent_downloads.first
      name              = result[:name]
      bandwidth_by_date = result[:bandwidth_by_date]
      total_bandwidth   = result[:total_bandwidth]

      assert_equal "DELETED PACKAGES", name
      assert_equal 2, bandwidth_by_date.length # 2 download events
      # Order is not guaranteed in our actual usage of this method, but added a sort to make
      # it a little easier to test, the dates are from the expected data transfers above
      expected_ordered_dates = [::GitHub::Billing.today - 1.week, ::GitHub::Billing.today - 1.day]
      assert_equal expected_ordered_dates, bandwidth_by_date.keys.map(&:last).sort
      assert_equal expected_results_size, total_bandwidth
    end

    test "shows org package usage and missing packages distinctly" do
      user             = create(:user)
      repo             = create(:repository, from_example: :repository_test_simple)
      registry_package = create(:registry_package, repository: repo)

      last_day_date = T.cast(Time.now - 1.day, Time)
      last_week_date = T.cast(Time.now - 1.week, Time)
      byte_size = 1610612736

      usage_line_items = []
      [last_day_date, last_week_date].each do |date|
        usage_line_items << create_mock_usage_line_item(
          usage_at: Google::Protobuf::Timestamp.new(seconds: date.to_i),
          repository_id: repo.id,
          billable_owner_id: user.id,
          quantity: byte_size,
          custom_fields: {
            "package.id": registry_package.id.to_s
          }
        )
        usage_line_items << create_mock_usage_line_item(
          usage_at: Google::Protobuf::Timestamp.new(seconds: (date).to_time.to_i),
          repository_id: repo.id,
          billable_owner_id: user.id,
          quantity: 1.megabyte,
          custom_fields: {
            "package.id": "0"
          }
        )
      end
      mock_get_usage_line_items_response_with(usage_line_items: usage_line_items)

      registry_package.delete

      expected_results_size = (2 * 1.megabyte) + (2 * byte_size)
      aggregator            = ::Billing::Stafftools::MeteredUsageAggregation.new(owner_id: user.id)
      recent_downloads      = aggregator.packages_bandwidth_since_cycle_reset

      assert_equal 2, recent_downloads.length
      assert_equal ::GitHub::Billing.today.beginning_of_month, user.current_metered_billing_cycle_starts_at.to_date

      result            = recent_downloads.first
      name              = result[:name]
      bandwidth_by_date = result[:bandwidth_by_date]
      total_bandwidth   = result[:total_bandwidth]

      assert_equal "DELETED PACKAGES", name
      assert_equal 2, bandwidth_by_date.length # 2 download events

      second_result = recent_downloads.second
      cr_name = second_result[:name]
      cr_bandwidth_by_date = second_result[:bandwidth_by_date]
      cr_total_bandwidth = second_result[:total_bandwidth]

      assert_equal "Organization Packages", cr_name
      assert_equal 2, cr_bandwidth_by_date.length # 2 download events

      # Order is not guaranteed in our actual usage of this method, but added a sort to make
      # it a little easier to test, the dates are from the expected data transfers above
      expected_ordered_dates = [::GitHub::Billing.today - 1.week, ::GitHub::Billing.today - 1.day]
      assert_equal expected_ordered_dates, cr_bandwidth_by_date.keys.map(&:last).sort
      assert_equal expected_results_size, total_bandwidth + cr_total_bandwidth
    end
  end

  context "copilot_usage_since_cycle_reset" do
    test "returns an array of hashes for copilot usage" do
      owner = create(:organization)

      aggregator = ::Billing::Stafftools::MeteredUsageAggregation.new(owner_id: owner.id)

      mock_line_item_1 = create_mock_usage_line_item(
        billable_owner_id: owner.id,
        quantity: 2,
        effective_quantity: 2,
        product_sku_name: "copilot_for_business",
        usage_at: Google::Protobuf::Timestamp.new(seconds: (GitHub::Billing.today - 1.week).to_time.to_i),
      )

      mock_line_item_2 = create_mock_usage_line_item(
        billable_owner_id: owner.id,
        quantity: 4,
        effective_quantity: 4,
        product_sku_name: "copilot_for_business",
        usage_at: Google::Protobuf::Timestamp.new(seconds: (GitHub::Billing.today - 2.days).to_time.to_i),
      )

      Billing::Api::ClientWrapper.any_instance.expects(:get_usage_line_items).times(1).with(
        has_key(:usage_starts_at)
      ).returns(
        Meuse::Services::V1::GetUsageLineItemsResponse.new(
          usage_line_items: [mock_line_item_1, mock_line_item_2]
        ).usage_line_items.to_a
      )

      recent_usage = aggregator.copilot_usage_since_cycle_reset

      assert_equal 2, recent_usage.count
      assert_equal 6, recent_usage.sum { |usage| usage[:quantity] }
    end
  end

  context "#actions_usage_since_cycle_reset" do
    test "returns an array of hashes with information around actions usage minutes" do
      owner = create(:user)
      _not_our_owner = create(:user)
      repository = create(:repository, owner: owner)

      mock_line_item_1 = create_mock_usage_line_item(
        billable_owner_id: owner.id,
        repository_id: repository.id,
        quantity: 5,
        effective_quantity: 5,
        product_sku_name: job_runtime_env_to_product_sku_name("UBUNTU"),
        usage_at: Google::Protobuf::Timestamp.new(seconds: (GitHub::Billing.today - 1.week).to_time.to_i),
        custom_fields: {
          "actions.workflow.id": "12345"
        }
      )

      mock_line_item_2 = create_mock_usage_line_item(
        billable_owner_id: owner.id,
        repository_id: repository.id,
        quantity: 5,
        effective_quantity: 50, # the multiplier for macos is 10, so 5 * 10 = 50
        product_sku_name: job_runtime_env_to_product_sku_name("MACOS"),
        usage_at: Google::Protobuf::Timestamp.new(seconds: (GitHub::Billing.today - 1.week).to_time.to_i),
        custom_fields: {
          "actions.workflow.id": "54321"
        }
      )

      Billing::Api::ClientWrapper.any_instance.expects(:get_usage_line_items).times(1).with(
        has_key(:usage_starts_at)
      ).returns(
        Meuse::Services::V1::GetUsageLineItemsResponse.new(
          usage_line_items: [mock_line_item_1, mock_line_item_2]
        ).usage_line_items.to_a
      )

      expected_results_mins = mock_line_item_1[:effective_quantity] + mock_line_item_2[:effective_quantity]
      aggregator            = ::Billing::Stafftools::MeteredUsageAggregation.new(owner_id: owner.id)
      recent_usage          = aggregator.actions_usage_since_cycle_reset

      # One one package has downloads
      assert_equal 1, recent_usage.length
      assert_equal ::GitHub::Billing.today.beginning_of_month, owner.current_metered_billing_cycle_starts_at.to_date

      result              = recent_usage.first
      name                = result[:name]
      minutes_per_runtime = result[:minutes_per_runtime]
      total_minutes       = result[:total_minutes]

      assert_equal repository.name, name
      assert_equal 2, minutes_per_runtime.length # 2 usage line items
      assert_equal %w[MACOS UBUNTU], minutes_per_runtime.keys.map(&:last)
      assert_equal expected_results_mins, total_minutes
    end

    test "returns deleted repositories" do
      owner      = create(:user)
      repository = create(:deleted_repository, owner: owner)

      mock_line_item = create_mock_usage_line_item(
        billable_owner_id: owner.id,
        repository_id: repository.id,
        quantity: 5,
        effective_quantity: 5,
        product_sku_name: job_runtime_env_to_product_sku_name("UBUNTU"),
        usage_at: Google::Protobuf::Timestamp.new(seconds: (GitHub::Billing.today - 1.week).to_time.to_i),
        custom_fields: {
          "actions.workflow.id": "123"
        }
      )

      Billing::Api::ClientWrapper.any_instance.expects(:get_usage_line_items).times(1).with(
        has_key(:usage_starts_at)
      ).returns(
        Meuse::Services::V1::GetUsageLineItemsResponse.new(
          usage_line_items: [mock_line_item]
        ).usage_line_items.to_a
      )

      aggregator = ::Billing::Stafftools::MeteredUsageAggregation.new(owner_id: owner.id)
      recent_usage = aggregator.actions_usage_since_cycle_reset

      # One one package has downloads
      assert_equal 1, recent_usage.length
      assert_equal ::GitHub::Billing.today.beginning_of_month, owner.current_metered_billing_cycle_starts_at.to_date

      result = recent_usage.first
      name   = result[:name]

      assert_equal repository.name, name
    end
  end if GitHub.billing_enabled?
end
