# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::PrebuildStorageAnalyticsMessageHandlerTest < GitHub::TestCase
  include CodespacesPlanFixtures

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @owner = create(:credit_card_organization, plan: GitHub::Plan.business_plus)
    @repo = create(:private_repository, owner: @owner)
    @prebuild_template = create(:codespace_prebuild_template, repository: @repo)
    @billing_entry = @prebuild_template.billing_entry
    @vscs_target = "production"
    @billing_message = build(
      :codespace_ephemeral_billing_message,
      :without_compute,
      codespace_plan_id: @prebuild_template.plan.id,
      codespaces: [@prebuild_template]
    )
    @tracked_usage = @billing_message.tracked_usages_for(@billing_entry.prebuild_template_guid).find(&:is_storage?)
    @unique_billing_identifier = "#{@billing_message.event_id}-#{@billing_entry.prebuild_plan_name}-#{@billing_entry.prebuild_template_guid}-#{@tracked_usage.formatted_sku_name}"
  end

  context "#transform_storage_usage" do
    test "transforms the data" do
      expected = {
        owner_id: @billing_entry.billable_owner_id,
        actor_id: nil,
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
        accessible: nil,
        actor: nil,
        billing_plan_owner: Hydro::EntitySerializer.codespace_billable_owner(@billing_entry.billable_owner),
        codespace_id: nil,
        codespace_database_id: nil,
        region: @billing_message.location,
        storage_type: :PREBUILD,
      }
      result = Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:transform_storage_usage)

      assert_equal expected, result
    end
  end

  context "#publish_storage_usage" do
    test "calls instrument and instruments analytics event" do
      handler = Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)
      result = handler.send(:transform_storage_usage)
      GlobalInstrumenter.expects(:instrument).once.with(Codespaces::Events::BILLING_STORAGE_ANALYTICS, equals(storage_data: result))
      result = handler.perform
    end
  end

  context "#perform" do
    test "calls transform and publish" do
      Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler.any_instance.expects(:transform_storage_usage)
      Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler.any_instance.expects(:publish_storage_usage)
      Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    test "doesn't call transform or publish if the usage type is not storage" do
      tracked_usage = @billing_message.tracked_usages_for(@billing_entry.prebuild_template_guid).find(&:is_compute?)
      Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler.any_instance.expects(:transform_storage_usage).never
      Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler.any_instance.expects(:publish_storage_usage).never
      Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler.new(billing_message: @billing_message, tracked_usage: tracked_usage, billing_entry: @billing_entry).perform
    end
  end
end unless GitHub.enterprise?
