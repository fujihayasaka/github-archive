# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::StorageAnalyticsMessageHandlerTest < GitHub::TestCase

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
      vscs_target: @vscs_target
    )
    @tracked_usage = @billing_message.tracked_usages_for(@billing_entry.codespace_guid).find(&:is_storage?)
    @unique_billing_identifier = "#{@billing_message.event_id}-#{@billing_entry.codespace_plan_name}-#{@billing_entry.codespace_guid}-#{@tracked_usage.formatted_sku_name}"
  end

  context "#transform_storage_usage" do
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
        size_in_bytes: @tracked_usage.size_in_bytes,
        vscs_target: @vscs_target,
        accessible: true,
        actor: Hydro::EntitySerializer.user(@billing_entry.codespace_owner),
        billing_plan_owner: Hydro::EntitySerializer.codespace_billable_owner(@billing_entry.billable_owner),
        codespace_id: @billing_entry.codespace&.guid,
        codespace_database_id: @billing_entry.codespace&.id,
        region: @billing_entry.codespace&.location,
        storage_type: :CODESPACE,
      }
      result = Codespaces::Billing::StorageAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:transform_storage_usage)

      assert_equal expected, result
    end

    test "transforms the data when the codespace was deleted" do

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
        size_in_bytes: @tracked_usage.size_in_bytes,
        vscs_target: @vscs_target,
        accessible: false,
        actor: Hydro::EntitySerializer.user(@billing_entry.codespace_owner),
        billing_plan_owner: Hydro::EntitySerializer.codespace_billable_owner(@billing_entry.billable_owner),
        codespace_id: @billing_entry.codespace&.guid,
        codespace_database_id: @billing_entry.codespace&.id,
        region: @billing_entry.codespace&.location,
        storage_type: :CODESPACE,
      }
      result = Codespaces::Billing::StorageAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:transform_storage_usage)

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
        size_in_bytes: @tracked_usage.size_in_bytes,
        vscs_target: @vscs_target,
        accessible: true,
        actor: Hydro::EntitySerializer.user(@billing_entry.codespace_owner),
        billing_plan_owner: Hydro::EntitySerializer.codespace_billable_owner(@billing_entry.billable_owner),
        codespace_id: @billing_entry.codespace&.guid,
        codespace_database_id: @billing_entry.codespace&.id,
        region: @billing_entry.codespace&.location,
        storage_type: :CODESPACE,
        copilot_workspace_id: test_cw_id,
      }
      result = Codespaces::Billing::StorageAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:transform_storage_usage)

      assert_equal expected, result
    end
  end

  context "#publish_storage_usage" do
    test "calls instrument and instruments analytics event" do
      handler = Codespaces::Billing::StorageAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)
      result = handler.send(:transform_storage_usage)
      GlobalInstrumenter.expects(:instrument).once.with(Codespaces::Events::BILLING_STORAGE_ANALYTICS, equals(storage_data: result))
      result = handler.perform
    end
  end

  context "#perform" do
    test "calls transform and publish" do
      Codespaces::Billing::StorageAnalyticsMessageHandler.any_instance.expects(:transform_storage_usage)
      Codespaces::Billing::StorageAnalyticsMessageHandler.any_instance.expects(:publish_storage_usage)
      Codespaces::Billing::StorageAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    test "doesn't call transform or publish if the usage type is not storage" do
      tracked_usage = @billing_message.tracked_usages_for(@billing_entry.codespace_guid).find(&:is_compute?)
      Codespaces::Billing::StorageAnalyticsMessageHandler.any_instance.expects(:transform_storage_usage).never
      Codespaces::Billing::StorageAnalyticsMessageHandler.any_instance.expects(:publish_storage_usage).never
      Codespaces::Billing::StorageAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: tracked_usage, billing_entry: @billing_entry).perform
    end
  end
end unless GitHub.enterprise?
