# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::StorageVNextMessageHandlerTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    user = create(:user)
    @billable_owner = create(:invoiced_organization)
    repository = create(:repository, owner: @billable_owner)
    @billable_owner.add_member(user)
    @codespace = create(:codespace, owner: user, repository: repository)
    @vscs_target = "production"
    billing_data = create_billing_data(user, vscs_target: @vscs_target, codespace: @codespace)
    @billing_entry = billing_data[:billing_entry]
    @billing_message = billing_data[:billing_message]
    @tracked_usage = billing_data[:tracked_usage]
    disable_feature_flag(:codespaces_billing_free)
  end


  context "#transform_usage" do
    test "puts data in expected format" do
      unique_billing_identifier = "Codespaces/Storage/#{@billing_message.event_id}-#{@billing_entry.codespace_plan_name}-#{@billing_entry.codespace_guid}-#{@tracked_usage.formatted_sku_name}-#{@billing_message.period_start}"
      handler = Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)

      expected = {
        sku: "codespaces_storage",
        quantity: @tracked_usage.computed_usage_in_gb_month,
        usage_at: Google::Protobuf::Timestamp.new(seconds: @billing_message.period_end.to_i, nanos: 0),
        source_uri: @billing_message.source_uri,
        entity: {
          customer_id: @billable_owner.customer.id,
          organization_id: @billing_entry.repository&.organization_id,
          repo_id: @billing_entry.repository_id,
          actor_id: @billing_entry.codespace_owner_id,
        },
        usage_uuid: ::Billing::MeteredProduct.usage_uuid(unique_billing_identifier)
      }
      result = handler.send(:transform_usage)
      assert_equal expected, result
    end

    test "send appropriate fields when codespace owned by enterprise" do
      member = create :user
      org = create :organization, admins: [member]
      repository = create :repository, owner: org
      enterprise = create :business, owners: [member], organizations: [org]
      codespace = create(:codespace, owner: member, repository: repository)
      billing_data = create_billing_data(member, vscs_target: "production", codespace: codespace)
      billing_entry = billing_data[:billing_entry]
      billing_message = billing_data[:billing_message]
      tracked_usage = billing_data[:tracked_usage]

      handler = Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: billing_message, tracked_usage: tracked_usage, billing_entry: billing_entry)
      result = handler.send(:transform_usage)
      assert enterprise.customer_id
      assert org.id
      assert_equal(result[:entity][:customer_id], enterprise.customer_id)
      assert_equal(result[:entity][:organization_id], org.id)
      assert_equal(result[:entity][:actor_id], member.id)
    end
  end

  context "#publish_usage" do
    test "returns result to publish" do
      data = {
        test_data: true,
      }

      handler = Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)
      result = handler.send(:publish_usage, data)

      assert_equal(result.hydro_topic, "billingplatform.v1.Usage")
      assert_equal data, result.hydro_payload

    end
  end

  context "#transform_usage_for_splunk" do
    test "transforms nested hash to flat and uses semconv keys" do
      data = {
        sku: "sku",
        quantity: "quantity",
        usage_at: Google::Protobuf::Timestamp.new(seconds: @billing_message.period_end.to_i, nanos: 0),
        source_uri: "source_uri",
        entity: {
          customer_id: "customer_id",
          organization_id: "organization_id",
          repo_id: "repo_id",
          actor_id: "actor_id",
        },
        usage_uuid: "usage_uuid",
      }

      expected = {
        "gh.codespaces.billing_message.product_sku_name" => "sku",
        "gh.codespaces.billing_message.quantity" => "quantity",
        "gh.codespaces.billing_message.usage_at.seconds" => @billing_message.period_end.to_i,
        "gh.codespaces.billing_message.usage_at.nanos" => 0,
        "gh.codespaces.billing_message.source_uri" => "source_uri",
        "gh.billing.customer.id" => "customer_id",
        "gh.org.id" => "organization_id",
        "gh.repo.id" => "repo_id",
        "gh.user.id" => "actor_id",
        "gh.codespaces.billing_message.usage_uuid" => "usage_uuid",
      }

      handler = Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)
      result = handler.send(:transform_usage_for_splunk, data)
      assert_equal(expected, result)
    end
  end

  context "#should_publish?" do
    test "returns false if CW codespace storage message" do
      cw = create(:copilot_workspace)
      billing_data = create_billing_data(cw.owner, vscs_target: "production", codespace: cw)
      billing_entry = billing_data[:billing_entry]
      billing_message = billing_data[:billing_message]
      tracked_usage = billing_message.tracked_usages_for(billing_entry.codespace_guid).find(&:is_storage?)
      refute Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: billing_message, tracked_usage: tracked_usage, billing_entry: billing_entry).send(:should_publish?)
    end

    test "returns false if compute message" do
      tracked_usage = @billing_message.tracked_usages_for(@billing_entry.codespace_guid).find(&:is_compute?)
      refute Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false when billable owner is given free codespace usage" do
      enable_feature_flag(:codespaces_billing_free, @billing_entry.billable_owner&.billable_owner)
      refute Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns true when billable owner is a user" do
      user = create(:user)
      assert Codespaces::Billing::StorageVNextMessageHandler.new(**create_billing_data(user)).send(:should_publish?)
    end

    test "returns false when owner does not exist" do
      @billing_entry.stubs(:billable_owner).returns(nil)
      refute Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if the codespace does not exist and has not been deprovisioned" do
      @billing_entry.stubs(:codespace).returns(nil)
      @billing_entry.stubs(:codespace_deprovisioned_at).returns(nil)
      refute Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns true if the codespace does not exist and has been deprovisioned" do
      @billing_entry.stubs(:codespace).returns(nil)
      @billing_entry.stubs(:codespace_deprovisioned_at).returns(Time.current)
      assert Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if codespace not accessible" do
      @billing_entry.codespace.stubs(:accessible?).returns(false)
      refute Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if size in bytes isn't positive" do
      @tracked_usage.stubs(:size_in_bytes).returns(0)
      refute Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if duration in seconds isn't positive" do
      @tracked_usage.stubs(:billable_duration_in_seconds).returns(0)
      refute Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "otherwise returns true" do
      assert Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end
  end

  context "#perform" do
    test "calls additional methods if should_publish?" do
      Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:should_publish?).returns(true)
      Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:transform_usage)
      Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:publish_usage)

      Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    test "doesn't additional methods if the usage type if not should_publish?" do
      Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:should_publish?).returns(false)
      Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:transform_usage).never
      Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:publish_usage).never
      Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    context "if should_test_non_prod?" do
      test "does not log dev/ppe message if feature flag is disabled" do
        disable_feature_flag(:codespaces_billing_test_non_prod)
        @billing_message.stubs(:vscs_target).returns(:development)
        Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:publish_non_prod_usage).never
        Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:transform_usage).never
        Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end

      test "does not log dev/ppe message if it should not be published" do
        enable_feature_flag(:codespaces_billing_test_non_prod)
        @billing_message.stubs(:vscs_target).returns(:development)
        @billing_entry.stubs(:billable_owner).returns(nil)
        Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:publish_non_prod_usage).never
        Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:transform_usage).never
        Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end

      test "logs for dev/ppe if should normally publish & feature flag is on" do
        enable_feature_flag(:codespaces_billing_test_non_prod)
        @billing_message.stubs(:vscs_target).returns(:development)
        Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:publish_non_prod_usage)
        Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::StorageVNextMessageHandler.any_instance.expects(:transform_usage)
        Codespaces::Billing::StorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
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
      period_start: Time.now,
    )
    billing_entry = codespace.billing_entry
    tracked_usage = billing_message.tracked_usages_for(billing_entry.codespace_guid).find(&:is_storage?)
    { billing_message:, billing_entry:, tracked_usage: }
  end
end unless GitHub.enterprise?
