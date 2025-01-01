# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::ComputeAnalyticsMessageHandlerTest < GitHub::TestCase

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    user = create(:user)
    @codespace = create(:codespace, owner: user)
    @billing_entry = @codespace.billing_entry
    @vscs_target = "production"
    @billing_message = build(
      :codespace_ephemeral_billing_message,
      codespaces: [@codespace],
      codespace_plan_id: @codespace.plan.id,
      caller_name: "codespaces/dispatch_billing_message",
      vscs_target: @vscs_target,
      period_start: Time.now,
    )
    @tracked_usage = @billing_message.tracked_usages_for(@billing_entry.codespace_guid).find(&:is_compute?)
    @unique_billing_identifier = "#{@billing_message.event_id}-#{@billing_entry.codespace_plan_name}-#{@billing_entry.codespace_guid}-#{@tracked_usage.formatted_sku_name}-#{@billing_message.period_start}"
  end

  context "#transform_compute_usage" do
    test "transforms the data" do
      expected = {
        owner_id: @billing_entry.billable_owner_id,
        actor_id: @billing_entry.codespace_owner_id,
        billable_duration_in_seconds: @tracked_usage.billable_duration_in_seconds,
        source_uri: @billing_message.source_uri,
        start_time: @billing_message.period_start,
        end_time: @billing_message.period_end,
        unique_billing_identifier: @unique_billing_identifier,
        repository: Hydro::EntitySerializer.repository(@billing_entry.repository),
        sku: @tracked_usage.formatted_sku_name,
        computed_usage: 0,
        vscs_target: @vscs_target,
        accessible: true,
        cpu_core_count: Codespaces::Skus.sku_by_name(@tracked_usage.sku_name).cpus,
        gpu_core_count: Codespaces::Skus.sku_by_name(@tracked_usage.sku_name).gpus,
        actor: Hydro::EntitySerializer.user(@billing_entry.codespace_owner),
        billing_plan_owner: Hydro::EntitySerializer.codespace_billable_owner(@billing_entry.billable_owner),
        codespace_id: @billing_entry.codespace&.guid,
        codespace_database_id: @billing_entry.codespace&.id,
        region: @billing_entry.codespace&.location,
      }
      result = Codespaces::Billing::ComputeAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:transform_compute_usage)

      assert_equal expected, result
    end

    test "transforms the data when the codespace was deleted" do
      codespace_guid = @billing_entry.codespace.guid
      # Skips soft-deleting and deprovisioning flows
      @billing_entry.codespace.delete
      @billing_entry.reload

      expected = {
        owner_id: @billing_entry.billable_owner_id,
        actor_id: @billing_entry.codespace_owner_id,
        billable_duration_in_seconds: @tracked_usage.billable_duration_in_seconds,
        source_uri: @billing_message.source_uri,
        start_time: @billing_message.period_start,
        end_time: @billing_message.period_end,
        unique_billing_identifier: @unique_billing_identifier,
        repository: Hydro::EntitySerializer.repository(@billing_entry.repository),
        sku: @tracked_usage.formatted_sku_name,
        computed_usage: 0,
        vscs_target: @vscs_target,
        accessible: false,
        cpu_core_count: Codespaces::Skus.sku_by_name(@tracked_usage.sku_name).cpus,
        gpu_core_count: Codespaces::Skus.sku_by_name(@tracked_usage.sku_name).gpus,
        actor: Hydro::EntitySerializer.user(@billing_entry.codespace_owner),
        billing_plan_owner: Hydro::EntitySerializer.codespace_billable_owner(@billing_entry.billable_owner),
        codespace_id: codespace_guid,
        codespace_database_id: nil,
        region: nil,
      }
      result = Codespaces::Billing::ComputeAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:transform_compute_usage)

      assert_equal expected, result
    end

    test "transforms the data when the codespace was soft-deleted" do
      # To allow the soft-delete to happen in all-features tests
      disable_feature_flag(:codespaces_pause_deletions_user_requested)
      codespace_guid = @billing_entry.codespace.guid
      codespace_id = @billing_entry.codespace.id
      codespace_region = @billing_entry.codespace.location
      # Soft-delete the codespace and then run enqueued jobs since `deprovision`
      # does the soft-delete inside of a background job. This replicates the way
      # most codespaces are actually deleted.
      @billing_entry.codespace.deprovision!
      perform_enqueued_jobs only: CodespacesDeleteJob
      @billing_entry.reload

      expected = {
        owner_id: @billing_entry.billable_owner_id,
        actor_id: @billing_entry.codespace_owner_id,
        billable_duration_in_seconds: @tracked_usage.billable_duration_in_seconds,
        source_uri: @billing_message.source_uri,
        start_time: @billing_message.period_start,
        end_time: @billing_message.period_end,
        unique_billing_identifier: @unique_billing_identifier,
        repository: Hydro::EntitySerializer.repository(@billing_entry.repository),
        sku: @tracked_usage.formatted_sku_name,
        computed_usage: 0.0,
        vscs_target: @vscs_target,
        accessible: false,
        cpu_core_count: Codespaces::Skus.sku_by_name(@tracked_usage.sku_name).cpus,
        gpu_core_count: Codespaces::Skus.sku_by_name(@tracked_usage.sku_name).gpus,
        actor: Hydro::EntitySerializer.user(@billing_entry.codespace_owner),
        billing_plan_owner: Hydro::EntitySerializer.codespace_billable_owner(@billing_entry.billable_owner),
        codespace_id: codespace_guid,
        codespace_database_id: codespace_id,
        region: codespace_region,
      }
      result = Codespaces::Billing::ComputeAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:transform_compute_usage)

      assert_equal expected, result
    end

    test "includes copilot_workspace_id if extant" do
      test_cw_id = SecureRandom.hex(18)
      @billing_entry.codespace.update!(copilot_workspace_id: test_cw_id)
      expected = {
        owner_id: @billing_entry.billable_owner_id,
        actor_id: @billing_entry.codespace_owner_id,
        billable_duration_in_seconds: @tracked_usage.billable_duration_in_seconds,
        source_uri: @billing_message.source_uri,
        start_time: @billing_message.period_start,
        end_time: @billing_message.period_end,
        unique_billing_identifier: @unique_billing_identifier,
        repository: Hydro::EntitySerializer.repository(@billing_entry.repository),
        sku: @tracked_usage.formatted_sku_name,
        computed_usage: 0,
        vscs_target: @vscs_target,
        accessible: true,
        cpu_core_count: Codespaces::Skus.sku_by_name(@tracked_usage.sku_name).cpus,
        gpu_core_count: Codespaces::Skus.sku_by_name(@tracked_usage.sku_name).gpus,
        actor: Hydro::EntitySerializer.user(@billing_entry.codespace_owner),
        billing_plan_owner: Hydro::EntitySerializer.codespace_billable_owner(@billing_entry.billable_owner),
        codespace_id: @billing_entry.codespace&.guid,
        codespace_database_id: @billing_entry.codespace&.id,
        region: @billing_entry.codespace&.location,
        copilot_workspace_id: test_cw_id,
      }
      result = Codespaces::Billing::ComputeAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:transform_compute_usage)

      assert_equal expected, result
    end
  end

  context "#publish_compute_usage" do
    test "calls instrument and instruments analytics event" do
      handler = Codespaces::Billing::ComputeAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)
      result = handler.send(:transform_compute_usage)
      GlobalInstrumenter.expects(:instrument).once.with(Codespaces::Events::BILLING_COMPUTE_ANALYTICS, equals(compute_data: result))
      result = handler.perform
    end
  end

  context "#perform" do
    test "calls transform and publish" do
      Codespaces::Billing::ComputeAnalyticsMessageHandler.any_instance.expects(:transform_compute_usage)
      Codespaces::Billing::ComputeAnalyticsMessageHandler.any_instance.expects(:publish_compute_usage)
      Codespaces::Billing::ComputeAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    test "doesn't call transform or publish if the usage type is not compute" do
      tracked_usage = @billing_message.tracked_usages_for(@billing_entry.codespace_guid).find(&:is_storage?)
      Codespaces::Billing::ComputeAnalyticsMessageHandler.any_instance.expects(:transform_compute_usage).never
      Codespaces::Billing::ComputeAnalyticsMessageHandler.any_instance.expects(:publish_compute_usage).never
      Codespaces::Billing::ComputeAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: tracked_usage, billing_entry: @billing_entry).perform
    end
  end
end unless GitHub.enterprise?
