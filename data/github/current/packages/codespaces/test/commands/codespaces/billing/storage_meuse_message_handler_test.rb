# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::StorageMeuseMessageHandlerTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    user = create(:user)
    billable_owner = create(:codespaces_credit_card_organization, plan: GitHub::Plan.business_plus)
    repository = create(:repository, owner: billable_owner)
    billable_owner.add_member(user)
    @codespace = create(:codespace, owner: user, repository: repository)
    @billing_entry = @codespace.billing_entry
    @vscs_target = "production"
    billing_data = create_billing_data(user, vscs_target: @vscs_target, codespace: @codespace)
    @billing_entry = billing_data[:billing_entry]
    @billing_message = billing_data[:billing_message]
    @tracked_usage = billing_data[:tracked_usage]
    GitHub.flipper[:codespaces_billing_free].disable
  end


  context "#transform_usage" do
    test "transforms the data" do
      unique_billing_identifier = "Codespaces/Storage/#{@billing_message.event_id}-#{@billing_entry.codespace_plan_name}-#{@billing_entry.codespace_guid}-#{@tracked_usage.formatted_sku_name}"
      handler = Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)
      custom_fields = {
        "repository.id" => @billing_entry.repository_id,
      }
      expected = {
        usage_uuid: GitHub::Billing::MeteredProduct.usage_uuid(unique_billing_identifier),
        product_name: "codespaces",
        product_sku_name: "storage",
        usage_at: @billing_message.period_end,
        quantity: @tracked_usage.computed_usage_in_gb_month,
        account_id: @billing_entry.billable_owner_id,
        actor_id: @billing_entry.codespace_owner_id,
        source_uri: @billing_message.source_uri,
        custom_fields: custom_fields,
      }
      result = handler.send(:transform_usage)
      assert_equal expected, result
    end
  end

  context "#publish_usage" do

    test "return data for hydro" do
      data = {
        test_data: true,
      }

      result = Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:publish_usage, data)
      assert_equal(result.hydro_topic, "meuse.metered_usage")
      assert_equal(result.hydro_payload, data)
    end
  end

  context "#should_publish?" do
    test "returns false if CW codespace storage message" do
      cw = create(:copilot_workspace)
      billing_data = create_billing_data(cw.owner, vscs_target: "production", codespace: cw)
      billing_entry = billing_data[:billing_entry]
      billing_message = billing_data[:billing_message]
      tracked_usage = billing_message.tracked_usages_for(billing_entry.codespace_guid).find(&:is_storage?)
      refute Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: billing_message, tracked_usage: tracked_usage, billing_entry: billing_entry).send(:should_publish?)
    end

    test "returns false if compute message" do
      tracked_usage = @billing_message.tracked_usages_for(@billing_entry.codespace_guid).find(&:is_compute?)
      refute Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false when billable owner is given free codespace usage" do
      GitHub.flipper[:codespaces_billing_free].enable(@billing_entry.billable_owner&.billable_owner)
      refute Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns true when billable owner is a user" do
      user = create(:user)
      assert Codespaces::Billing::StorageMeuseMessageHandler.new(**create_billing_data(user)).send(:should_publish?)
    end

    test "returns false when owner does not exist" do
      @billing_entry.stubs(:billable_owner).returns(nil)
      refute Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if the codespace does not exist and has not been deprovisioned" do
      @billing_entry.stubs(:codespace).returns(nil)
      @billing_entry.stubs(:codespace_deprovisioned_at).returns(nil)
      refute Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns true if the codespace does not exist and has been deprovisioned" do
      @billing_entry.stubs(:codespace).returns(nil)
      @billing_entry.stubs(:codespace_deprovisioned_at).returns(Time.current)
      assert Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if codespace not accessible" do
      @billing_entry.codespace.stubs(:accessible?).returns(false)
      refute Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if size in bytes isn't positive" do
      @tracked_usage.stubs(:size_in_bytes).returns(0)
      refute Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if duration in seconds isn't positive" do
      @tracked_usage.stubs(:billable_duration_in_seconds).returns(0)
      refute Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "otherwise returns true" do
      assert Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end
  end

  context "#perform" do
    test "calls additional methods if should_publish?" do
      Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:should_publish?).returns(true)
      Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:transform_usage)
      Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:publish_usage)

      Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    test "doesn't additional methods if the usage type if not should_publish?" do
      Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:should_publish?).returns(false)
      Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:transform_usage).never
      Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:publish_usage).never
      Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    context "if should_test_non_prod?" do
      test "does not log dev/ppe message if feature flag is disabled" do
        GitHub.flipper[:codespaces_billing_test_non_prod].disable
        @billing_message.stubs(:vscs_target).returns(:development)
        Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:test_non_prod_usage).never
        Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:transform_usage).never
        Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end

      test "does not log dev/ppe message if it should not be published" do
        GitHub.flipper[:codespaces_billing_test_non_prod].enable
        @billing_message.stubs(:vscs_target).returns(:development)
        @billing_entry.stubs(:billable_owner).returns(nil)
        Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:test_non_prod_usage).never
        Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:transform_usage).never
        Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end

      test "logs for dev/ppe if should normally publish & feature flag is on" do
        GitHub.flipper[:codespaces_billing_test_non_prod].enable
        @billing_message.stubs(:vscs_target).returns(:development)
        Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:test_non_prod_usage)
        Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::StorageMeuseMessageHandler.any_instance.expects(:transform_usage)
        Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end
    end
  end

  def create_billing_data(user, vscs_target: "production", codespace: create(:codespace, owner: user))
    billing_message = build(
      :codespace_ephemeral_billing_message,
      codespaces: [codespace],
      codespace_plan_id: codespace.plan.id,
      caller_name: "codespaces/dispatch_billing_message",
      vscs_target:,
    )
    billing_entry = codespace.billing_entry
    tracked_usage = billing_message.tracked_usages_for(billing_entry.codespace_guid).find(&:is_storage?)
    { billing_message:, billing_entry:, tracked_usage: }
  end
end unless GitHub.enterprise?
