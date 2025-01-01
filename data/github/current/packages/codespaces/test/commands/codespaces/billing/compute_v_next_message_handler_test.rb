# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::ComputeVNextMessageHandlerTest < GitHub::TestCase
  include DogstatsTestHelpers
  include ::Billing::ApiTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    user = create(:user)
    @billable_owner = create(:invoiced_organization)
    repository = create(:repository, owner: @billable_owner)
    @billable_owner.add_member(user)
    @codespace = create(:codespace, owner: user, repository: repository, sku_name: :standardLinux32gb)
    @billing_entry = @codespace.billing_entry
    @vscs_target = "production"
    billing_data = create_billing_data(user, vscs_target: @vscs_target, codespace: @codespace)
    @billing_entry = billing_data[:billing_entry]
    @billing_message = billing_data[:billing_message]
    @tracked_usage = billing_data[:tracked_usage]
    GitHub.flipper[:codespaces_billing_free].disable
  end

  context "#transform_usage" do
    test "puts data in expected format" do
      unique_billing_identifier = "Codespaces/Compute/#{@billing_message.event_id}-#{@billing_entry.codespace_plan_name}-#{@billing_entry.codespace_guid}-#{@tracked_usage.formatted_sku_name}"
      handler = Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)

      expected = {
        sku: "codespaces_compute_d2",
        quantity: @tracked_usage.billable_duration_in_hours,
        usage_at: Google::Protobuf::Timestamp.new(seconds: @billing_message.period_end.to_i, nanos: 0),
        source_uri: @billing_message.source_uri,
        entity: {
          customer_id: @billable_owner.customer.id,
          organization_id: @billing_entry.repository&.organization_id,
          repo_id: @billing_entry.repository_id,
          actor_id: @billing_entry.codespace_owner_id,
        },
        usage_uuid: GitHub::Billing::MeteredProduct.usage_uuid(unique_billing_identifier)
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

      handler = Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: billing_message, tracked_usage: tracked_usage, billing_entry: billing_entry)
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

      handler = Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)
      result = handler.send(:publish_usage, data)

      assert_equal(result.hydro_topic, "billingplatform.v1.Usage")
      assert_equal data, result.hydro_payload

    end
  end

  context "#perform" do
    test "updates datadog stat" do
      handler = Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)
      handler.expects(:should_publish?).once.returns(true)

      handler.perform

      assert_dogstats_increment 1, "codespaces.billing_usage.dispatched.count",
        tags: ["class:codespaces/billing/compute_v_next_message_handler"]
    end

    test "calls #check_usage_limit" do
      handler = Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)
      handler.expects(:should_publish?).once.returns(true)
      handler.expects(:check_usage_limit).once
      handler.perform
    end
  end

  context "#should_publish?" do
    test "returns false if CW codespace compute message" do
      cw = create(:copilot_workspace, sku_name: :standardLinux32gb)
      billing_data = create_billing_data(cw.owner, vscs_target: "production", codespace: cw)
      billing_entry = billing_data[:billing_entry]
      billing_message = billing_data[:billing_message]
      tracked_usage = billing_message.tracked_usages_for(billing_entry.codespace_guid).find(&:is_compute?)
      refute Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: billing_message, tracked_usage: tracked_usage, billing_entry: billing_entry).send(:should_publish?)
    end

    test "returns false if storage message" do
      tracked_usage = @billing_message.tracked_usages_for(@billing_entry.codespace_guid).find(&:is_storage?)
      refute Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false when billing billable owner is given free codespace usage" do
      GitHub.flipper[:codespaces_billing_free].enable(@billing_entry.billable_owner&.billable_owner)
      refute Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false when codespace billable owner is given free codespace usage and FF is enabled" do
      GitHub.flipper[:codespaces_billing_free].enable(@billing_entry.billable_owner)
      GitHub.flipper[:codespaces_billable_owner_free_direct_check].enable(@billing_entry.billable_owner)
      refute Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns true when billable owner is a user " do
      user = create(:user)
      assert Codespaces::Billing::ComputeVNextMessageHandler.new(**create_billing_data(user)).send(:should_publish?)
    end

    test "returns false when owner does not exist" do
      @billing_entry.stubs(:billable_owner).returns(nil)
      refute Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false for an unbillable SKU" do
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("standardLinuxNcv3"))
      refute Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false and sends failbot error for an unrecognized SKU" do
      @tracked_usage.stubs(:sku).returns(nil)
      assert_equal(0, Failbot.reports.size)
      refute Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
      assert_equal(1, Failbot.reports.size)
    end

    test "returns false if the codespace does not exist and has not been deprovisioned" do
      @billing_entry.stubs(:codespace).returns(nil)
      @billing_entry.stubs(:codespace_deprovisioned_at).returns(nil)
      refute Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns true if the codespace does not exist and has been deprovisioned" do
      @billing_entry.stubs(:codespace).returns(nil)
      @billing_entry.stubs(:codespace_deprovisioned_at).returns(Time.current)
      assert Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if codespace not accessible" do
      @billing_entry.codespace.stubs(:accessible?).returns(false)
      refute Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if billable duration isn't positive" do
      @tracked_usage.stubs(:billable_duration_in_seconds).returns(0)
      refute Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "otherwise returns true" do
      assert Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end
  end

  context "#perform" do
    test "calls additional methods if should_publish?" do
      Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:should_publish?).returns(true)
      Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:transform_usage)
      Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:publish_usage)

      Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    test "doesn't additional methods if the usage type if not should_publish?" do
      Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:should_publish?).returns(false)
      Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:transform_usage).never
      Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:publish_usage).never
      Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    context "if should_test_non_prod?" do
      test "does not log dev/ppe message if feature flag is disabled" do
        GitHub.flipper[:codespaces_billing_test_non_prod].disable
        @billing_message.stubs(:vscs_target).returns(:development)
        Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:publish_non_prod_usage).never
        Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:transform_usage).never
        Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end

      test "does not log dev/ppe message if it should not be published" do
        GitHub.flipper[:codespaces_billing_test_non_prod].enable
        @billing_message.stubs(:vscs_target).returns(:development)
        @billing_entry.stubs(:billable_owner).returns(nil)
        Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:publish_non_prod_usage).never
        Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:transform_usage).never
        Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end

      test "logs for dev/ppe if should normally publish & feature flag is on" do
        GitHub.flipper[:codespaces_billing_test_non_prod].enable
        @billing_message.stubs(:vscs_target).returns(:development)
        Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:publish_non_prod_usage)
        Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::ComputeVNextMessageHandler.any_instance.expects(:transform_usage)
        Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end
    end
  end

  context "#sku" do
    test "maps each SKU to the expected product sku" do
      handler = Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)

      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("basicLinux"))
      assert_equal("codespaces_compute_d2", handler.send(:billing_sku))
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("basicLinux32gb"))
      assert_equal("codespaces_compute_d2", handler.send(:billing_sku))

      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("standardLinux"))
      assert_equal("codespaces_compute_d4", handler.send(:billing_sku))
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("standardLinux32gb"))
      assert_equal("codespaces_compute_d4", handler.send(:billing_sku))

      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("premiumLinux"))
      assert_equal("codespaces_compute_d8", handler.send(:billing_sku))
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("premiumLinux32gb"))
      assert_equal("codespaces_compute_d8", handler.send(:billing_sku))

      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("largePremiumLinux"))
      assert_equal("codespaces_compute_d16", handler.send(:billing_sku))
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("largePremiumLinux256gb"))
      assert_equal("codespaces_compute_d16", handler.send(:billing_sku))

      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("extremeLinux"))
      assert_equal("codespaces_compute_d32", handler.send(:billing_sku))
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("xLargePremiumLinux"))
      assert_equal("codespaces_compute_d32", handler.send(:billing_sku))
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("xLargePremiumLinux256gb"))
      assert_equal("codespaces_compute_d32", handler.send(:billing_sku))
    end

    test "returns nil when the SKU is not valid" do
      handler = Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)

      @tracked_usage.stubs(:sku).returns(nil)
      assert_nil(handler.send(:billing_sku))
    end

    test "returns nil when the SKU has unexpected number of cpus" do
      handler = Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)

      @tracked_usage.sku.stubs(:cpus).returns(100)
      assert_nil(handler.send(:billing_sku))
    end
  end

  context "#check_usage_limit" do
    test "enqueues spending limit check" do
      mock_job = mock("Codespaces::SuspendCodespaceAtUsageLimitJob")
      Codespaces::SuspendCodespaceAtUsageLimitJob.expects(:set).with(wait: 15.minutes).returns(mock_job)
      mock_job.expects(:perform_later).with(codespace: @codespace)

      Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    test "does not enqueue spending limit check when codespace is nil" do
      Codespaces::SuspendCodespaceAtUsageLimitJob.expects(:set).never
      Codespaces::SuspendCodespaceAtUsageLimitJob.any_instance.expects(:perform_later).never

      @billing_entry.codespace = nil

      Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
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
    tracked_usage = billing_message.tracked_usages_for(billing_entry.codespace_guid).find(&:is_compute?)
    { billing_message:, billing_entry:, tracked_usage: }
  end
end unless GitHub.enterprise?
