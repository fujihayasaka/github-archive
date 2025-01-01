# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::ComputeMeuseMessageHandlerTest < GitHub::TestCase
  include DogstatsTestHelpers
  include ::Billing::ApiTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    user = create(:user)
    billable_owner = create(:codespaces_enterprise_organization)
    repository = create(:repository, owner: billable_owner)
    billable_owner.add_member(user)
    @codespace = create(:codespace, owner: user, repository: repository)
    @billing_entry = @codespace.billing_entry
    @vscs_target = "production"
    billing_data = create_billing_data(user, vscs_target: @vscs_target, codespace: @codespace)
    @billing_entry = billing_data[:billing_entry]
    @billing_message = billing_data[:billing_message]
    @tracked_usage = billing_data[:tracked_usage]
    disable_feature_flag(:codespaces_billing_free)
  end

  context "#transform_usage" do
    test "transforms the data" do
      unique_billing_identifier = "Codespaces/Compute/#{@billing_message.event_id}-#{@billing_entry.codespace_plan_name}-#{@billing_entry.codespace_guid}-#{@tracked_usage.formatted_sku_name}-#{@billing_message.period_start}"
      handler = Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)
      custom_fields = {
        "repository.id" => @billing_entry.repository_id,
      }
      expected = {
        usage_uuid: ::Billing::MeteredProduct.usage_uuid(unique_billing_identifier),
        product_name: "codespaces",
        product_sku_name: handler.send(:product_sku_name),
        usage_at: @billing_message.period_end,
        quantity: @tracked_usage.billable_duration_in_hours,
        account_id: @billing_entry.billable_owner_id,
        actor_id: @billing_entry.codespace_owner_id,
        source_uri: @billing_message.source_uri,
        custom_fields: custom_fields,
      }
      result = handler.send(:transform_usage)
      assert_equal expected, result
    end
  end

  context "#product_sku_name" do
    test "maps each SKU to the expected product sku" do
      handler = Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)

      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("basicLinux"))
      assert_equal(:compute_d2, handler.send(:product_sku_name))
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("basicLinux32gb"))
      assert_equal(:compute_d2, handler.send(:product_sku_name))

      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("standardLinux"))
      assert_equal(:compute_d4, handler.send(:product_sku_name))
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("standardLinux32gb"))
      assert_equal(:compute_d4, handler.send(:product_sku_name))

      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("premiumLinux"))
      assert_equal(:compute_d8, handler.send(:product_sku_name))
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("premiumLinux32gb"))
      assert_equal(:compute_d8, handler.send(:product_sku_name))

      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("largePremiumLinux"))
      assert_equal(:compute_d16, handler.send(:product_sku_name))
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("largePremiumLinux256gb"))
      assert_equal(:compute_d16, handler.send(:product_sku_name))

      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("extremeLinux"))
      assert_equal(:compute_d32, handler.send(:product_sku_name))
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("xLargePremiumLinux"))
      assert_equal(:compute_d32, handler.send(:product_sku_name))
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("xLargePremiumLinux256gb"))
      assert_equal(:compute_d32, handler.send(:product_sku_name))
    end

    test "returns nil when the SKU is nil" do
      handler = Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)

      @tracked_usage.stubs(:sku).returns(nil)
      assert_nil(handler.send(:product_sku_name))
    end
  end

  context "#publish_usage" do

    test "return data for hydro" do

      data = {
        test_data: true,
      }

      result = Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:publish_usage, data)
      assert_equal(result.hydro_topic, "meuse.metered_usage")
      assert_equal(result.hydro_payload, data)
    end

    test "updates datadog stat" do
      handler = Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)
      handler.stubs(:should_publish?).returns(true)

      handler.perform

      assert_dogstats_increment 1, "codespaces.billing_usage.dispatched.count",
        tags: ["class:codespaces/billing/compute_meuse_message_handler"]
    end
  end

  context "#should_publish?" do
    test "returns false if CW codespace compute message" do
      cw = create(:copilot_workspace, sku_name: :standardLinux32gb)
      billing_data = create_billing_data(cw.owner, vscs_target: "production", codespace: cw)
      billing_entry = billing_data[:billing_entry]
      billing_message = billing_data[:billing_message]
      tracked_usage = billing_message.tracked_usages_for(billing_entry.codespace_guid).find(&:is_compute?)
      refute Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: billing_message, tracked_usage: tracked_usage, billing_entry: billing_entry).send(:should_publish?)
    end

    test "returns false if storage message" do
      tracked_usage = @billing_message.tracked_usages_for(@billing_entry.codespace_guid).find(&:is_storage?)
      refute Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false when billing billable owner is given free codespace usage" do
      enable_feature_flag(:codespaces_billing_free, @billing_entry.billable_owner&.billable_owner)
      refute Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false when codespace billable owner is given free codespace usage and FF is enabled" do
      enable_feature_flag(:codespaces_billing_free, @billing_entry.billable_owner)
      enable_feature_flag(:codespaces_billable_owner_free_direct_check, @billing_entry.billable_owner)
      refute Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns true when billable owner is a user " do
      user = create(:user)
      assert Codespaces::Billing::ComputeMeuseMessageHandler.new(**create_billing_data(user)).send(:should_publish?)
    end

    test "returns false when owner does not exist" do
      @billing_entry.stubs(:billable_owner).returns(nil)
      refute Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if the codespace does not exist and has not been deprovisioned" do
      @billing_entry.stubs(:codespace).returns(nil)
      @billing_entry.stubs(:codespace_deprovisioned_at).returns(nil)
      refute Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns true if the codespace does not exist and has been deprovisioned" do
      @billing_entry.stubs(:codespace).returns(nil)
      @billing_entry.stubs(:codespace_deprovisioned_at).returns(Time.current)
      assert Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if codespace not accessible" do
      @billing_entry.codespace.stubs(:accessible?).returns(false)
      refute Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if billable duration isn't positive" do
      @tracked_usage.stubs(:billable_duration_in_seconds).returns(0)
      refute Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false for an unbillable SKU" do
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("standardLinuxNcv3"))
      @tracked_usage.stubs(:formatted_sku_name).returns("STANDARD_LINUX_NCV3")
      refute Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false and sends failbot error for an unrecognized SKU" do
      @tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("NOT_A_SKU"))
      assert_equal(0, Failbot.reports.size)
      refute Codespaces::Billing::ComputeVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
      assert_equal(1, Failbot.reports.size)
    end

    test "otherwise returns true" do
      assert Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end
  end

  context "#perform" do
    test "calls additional methods if should_publish?" do
      Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.stubs(:should_publish?).returns(true)
      Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:transform_usage)
      Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:publish_usage)
      Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:notify_later_if_applicable)

      Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    test "doesn't call additional methods if the usage type if not should_publish?" do
      Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.stubs(:should_publish?).returns(false)
      Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:transform_usage).never
      Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:publish_usage).never
      Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:notify_later_if_applicable).never
      Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    context "if should_test_non_prod?" do
      test "does not log dev/ppe message if feature flag is disabled" do
        disable_feature_flag(:codespaces_billing_test_non_prod)
        @billing_message.stubs(:vscs_target).returns(:development)
        Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:test_non_prod_usage).never
        Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:transform_usage).never
        Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:notify_later_if_applicable).never
        Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end

      test "does not log dev/ppe message if it should not be published" do
        enable_feature_flag(:codespaces_billing_test_non_prod)
        @billing_message.stubs(:vscs_target).returns(:development)
        @billing_entry.stubs(:billable_owner).returns(nil)
        Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:test_non_prod_usage).never
        Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:transform_usage).never
        Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:notify_later_if_applicable).never
        Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end

      test "logs for dev/ppe if should normally publish & feature flag is on" do
        enable_feature_flag(:codespaces_billing_test_non_prod)
        @billing_message.stubs(:vscs_target).returns(:development)
        Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:test_non_prod_usage)
        Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:transform_usage)
        Codespaces::Billing::ComputeMeuseMessageHandler.any_instance.expects(:notify_later_if_applicable)
        Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end
    end
  end

  context "#check_usage_limit" do
    test "enqueues spending limit check" do
      mock_job = mock("Codespaces::SuspendCodespaceAtUsageLimitJob")
      Codespaces::SuspendCodespaceAtUsageLimitJob.expects(:set).with(wait: 15.minutes).returns(mock_job)
      mock_job.expects(:perform_later).with(codespace: @codespace)

      Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    test "does not enqueue spending limit check when codespace is nil" do
      Codespaces::SuspendCodespaceAtUsageLimitJob.expects(:set).never
      Codespaces::SuspendCodespaceAtUsageLimitJob.any_instance.expects(:perform_later).never

      @billing_entry.codespace = nil

      Codespaces::Billing::ComputeMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
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
    tracked_usage = billing_message.tracked_usages_for(billing_entry.codespace_guid).find(&:is_compute?)
    { billing_message:, billing_entry:, tracked_usage: }
  end
end unless GitHub.enterprise?
