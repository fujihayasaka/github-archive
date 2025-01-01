# typed: ignore
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::DispatchMessageTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers
  include CodespacesPlanFixtures
  include GitHub::LoggerHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:credit_card_user)
    GitHub.flipper[:codespaces_billing_free].disable(@user)
    @codespace = create(:codespace, owner: @user)
    @billing_message = build(
      :codespace_ephemeral_billing_message,
      codespaces: [@codespace],
      codespace_plan_id: @codespace.plan.id,
      caller_name: "codespaces/billing/dispatch_message"
    )
    @storage_message = Codespaces::StorageClient::Message.new(
      id: SecureRandom.uuid,
      pop_receipt: SecureRandom.uuid,
      body: @billing_message.message_body,
      dequeue_count: 1,
      insertion_time: 1.minute.ago.iso8601,
      expiration_time: 1.minute.from_now.iso8601,
      time_next_visible: 2.minutes.from_now.iso8601,
    )
  end

  context "#call" do
    test "calls dispatch method for codespace billing message" do
      class Codespaces::EphemeralBillingMessage
        def ==(other)
          other.is_a?(self.class) && message_body == other.message_body && vscs_target == other.vscs_target && caller_name == other.caller_name && codespace_plan_id == other.codespace_plan_id
        end
        alias eql? ==
      end

      class Codespaces::BillingMessageTrackedUsage
        def ==(other)
          other.is_a?(self.class) && sku == other.sku && billable_duration_in_seconds == other.billable_duration_in_seconds && usage_type == other.usage_type && codespace_guid == other.codespace_guid
        end
        alias eql? ==
      end

      billing_entry = @codespace.billing_entry
      tracked_usages = @billing_message.tracked_usages_for(billing_entry.codespace_guid)
      Timecop.freeze do
        Codespaces::Billing::DispatchCodespaceMessage.expects(:call).with(billing_message: @billing_message, tracked_usages: tracked_usages, billing_entry: billing_entry)
        Codespaces::Billing::DispatchPrebuildMessage.expects(:call).with(billing_message: @billing_message, tracked_usages: tracked_usages, billing_entry: billing_entry)
        Codespaces::Billing::DispatchMessage.new(message: @storage_message.to_json, message_body: @billing_message.message_body, vscs_target: @codespace.vscs_target, codespace_plan_id: @codespace.plan.id).call
      end
    end

    test "publishes returned values to meuse" do
      Codespaces::Billing::DispatchMessage.new(message: @storage_message.to_json, message_body: @billing_message.message_body, vscs_target: @codespace.vscs_target, codespace_plan_id: @codespace.plan.id).call

      assert_hydro_published_partial({
        product_name: "codespaces",
        product_sku_name: "compute_d2",
        account_id: @user.id,
        actor_id: { value: @user.id },
        custom_fields: {
          "repository.id": @codespace.repository.id.to_s,
        }
      }, schema: "meuse.v0.MeteredUsage")
    end

    test "publishes returned values to v next" do
      @user.billing_customer.create_billing_platform_enabled_product(codespaces: true)
      unique_billing_identifier = "unique_billing_identifier"
      Codespaces::Billing::StorageVNextMessageHandler.any_instance.stubs(:unique_billing_identifier).returns(unique_billing_identifier)
      quantity = 292
      Codespaces::Billing::StorageVNextMessageHandler.any_instance.stubs(:quantity).returns(quantity)

      Codespaces::Billing::DispatchMessage.new(message: @storage_message.to_json, message_body: @billing_message.message_body, vscs_target: @codespace.vscs_target, codespace_plan_id: @codespace.plan.id).call

      assert_hydro_published_partial({
        sku: "codespaces_storage",
        quantity: quantity,
        usage_at: Google::Protobuf::Timestamp.new(seconds: @billing_message.period_end.to_i, nanos: 0),
        source_uri: @billing_message.source_uri,
        entity: {
          customer_id: @user.billing_customer.id,
          organization_id: @codespace.repository.organization_id,
          repo_id: @codespace.repository_id,
          actor_id: @user.id,
        },
        usage_uuid: GitHub::Billing::MeteredProduct.usage_uuid(unique_billing_identifier)
      }, schema: "billingplatform.v1.Usage")
    end

    test "the billing message drift time in seconds is instrumented when the message is processed" do
      freeze_time do
        billing_message = build(
          :codespace_ephemeral_billing_message,
          :without_compute,
          codespace_plan_id: @codespace.plan_id,
          codespaces: [@codespace],
          period_start: 2.hours.ago,
          period_end: period_end = 1.hour.ago
        )
        storage_message = Codespaces::StorageClient::Message.new(
          id: SecureRandom.uuid,
          pop_receipt: SecureRandom.uuid,
          body: billing_message.message_body,
          dequeue_count: 1,
          insertion_time: 1.minute.ago.iso8601,
          expiration_time: 1.minute.from_now.iso8601,
          time_next_visible: 2.minutes.from_now.iso8601,
        )
        Codespaces::Billing::DispatchMessage.new(message: storage_message.to_json, message_body: billing_message.message_body, vscs_target: billing_message.vscs_target, codespace_plan_id: @codespace.plan.id).call

        assert_dogstats_distribution 1, "codespaces.billing_message_drift_seconds.latency"
        assert_dogstats_distribution_value (billing_message.created_at.to_i - period_end.to_i), "codespaces.billing_message_drift_seconds.latency", tags: ["vscs_target:production"]
      end
    end

    test "above threshold, sends logs to splunk" do
      freeze_time do
        billing_message = build(
          :codespace_ephemeral_billing_message,
          :without_compute,
          codespace_plan_id: @codespace.plan_id,
          codespaces: [@codespace],
          period_start: 20.hours.ago,
          period_end: 10.hours.ago
        )
        storage_message = Codespaces::StorageClient::Message.new(
          id: SecureRandom.uuid,
          pop_receipt: SecureRandom.uuid,
          body: billing_message.message_body,
          dequeue_count: 1,
          insertion_time: 1.minute.ago.iso8601,
          expiration_time: 1.minute.from_now.iso8601,
          time_next_visible: 2.minutes.from_now.iso8601,
        )

        billing_message_drift_seconds = billing_message.created_at.to_i - billing_message.period_end.to_i

        GitHub.logger.expects(:warn).with("Billing message drift is too high", has_entries("code.namespace" => "Codespaces::Billing::DispatchMessage", "code.function" => "perform"))
        GitHub::Logger.expects(:log).with(has_entry(fn: "TrustTiers::Tier#for_billable_owner")).times(0..1)
        Codespaces::Billing::DispatchMessage.new(message: storage_message.to_json, message_body: billing_message.message_body, vscs_target: billing_message.vscs_target, codespace_plan_id: @codespace.plan.id).call
      end
    end

    context "invalid billing message" do
      test "raises MappingError before dispatch" do
        Codespaces::Billing::DispatchCodespaceMessage.expects(:call).never
        billing_message = build(
          :codespace_ephemeral_billing_message,
          :without_compute,
          codespace_plan_id: @codespace.plan_id,
          codespaces: [@codespace],
          period_start: 2.hours.ago,
          period_end: period_end = 1.hour.ago
        )
        storage_message = Codespaces::StorageClient::Message.new(
          id: SecureRandom.uuid,
          pop_receipt: SecureRandom.uuid,
          body: billing_message.message_body,
          dequeue_count: 1,
          insertion_time: 1.minute.ago.iso8601,
          expiration_time: 1.minute.from_now.iso8601,
          time_next_visible: 2.minutes.from_now.iso8601,
        )

        Codespaces::EphemeralBillingMessage.any_instance.stubs(:id).returns(nil)
        refute billing_message.valid?
        assert_raises Codespaces::Billing::DispatchMessage::MappingError do
          Codespaces::Billing::DispatchMessage.new(message: storage_message.to_json, message_body: billing_message.message_body, vscs_target: billing_message.vscs_target, codespace_plan_id: @codespace.plan.id).call
        end
      end
    end

    context "missing billing entry" do
      test "queues CodespacesCleanUpEnvironmentJob job and logs error" do
        Codespaces::ErrorReporter.expects(:report).once.with(instance_of(Codespaces::Billing::DispatchMessage::NoBillingEntryError))
        Codespaces::BillingEntry.where(codespace_guid: @codespace.guid).delete_all
        Codespaces::Billing::DispatchMessage.new(message: @storage_message.to_json, message_body: @billing_message.message_body, vscs_target: @codespace.vscs_target, codespace_plan_id: @codespace.plan.id).call

        assert_enqueued_jobs 1, only: CodespacesCleanUpEnvironmentJob, queue: :codespaces
        assert_enqueued_with job: CodespacesCleanUpEnvironmentJob, args: [plan_id: @codespace.plan.id, codespace_guid: @codespace.guid, vscs_target: :production, location: Codespaces::Locations::Region.find(@billing_message.location)&.id]
        assert_equal 1, GitHub.dogstats.increments("codespaces.missing_billing_entry", tags: ["vscs_target:production"]).length
      end

      test "does NOT queue CodespacesCleanUpEnvironmentJob job if non-production environment" do
        billing_message = build(
          :codespace_ephemeral_billing_message,
          codespace_plan_id: @codespace.plan_id,
          codespaces: [@codespace],
          vscs_target: "development"
        )
        storage_message = Codespaces::StorageClient::Message.new(
          id: SecureRandom.uuid,
          pop_receipt: SecureRandom.uuid,
          body: billing_message.message_body,
          dequeue_count: 1,
          insertion_time: 1.minute.ago.iso8601,
          expiration_time: 1.minute.from_now.iso8601,
          time_next_visible: 2.minutes.from_now.iso8601,
        )

        Codespaces::BillingEntry.where(codespace_guid: @codespace.guid).delete_all

        Codespaces::ErrorReporter.expects(:report).never
        Codespaces::Billing::DispatchMessage.new(message: storage_message.to_json, message_body: billing_message.message_body, vscs_target: billing_message.vscs_target, codespace_plan_id: @codespace.plan.id).call

        assert_enqueued_jobs 0, only: CodespacesCleanUpEnvironmentJob, queue: :codespaces
        assert_equal 1, GitHub.dogstats.increments("codespaces.missing_billing_entry", tags: ["vscs_target:development"]).length
      end
    end
  end
end unless GitHub.enterprise?
