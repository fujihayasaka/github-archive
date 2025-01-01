# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Actions::UsageLineItemWrapperTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers
  include GitHub::ComponentTestHelpers

  fixtures do
    make_trusted_oauth_apps_owner

    @repo = create(:repository)
    @check_suite = create(:check_suite_for_actions_app, repository: @repo)
    @check_run = create(:check_run,
      name: "check-run-name",
      check_suite: @check_suite,
      started_at: Time.now - 3.minutes,
      completed_at:  Time.now - 1.minute,
      conclusion: :success
    )
  end

  context "#job_runtime_environment" do
    test "returns the job_runtime_environment when it is linux" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU")
    end

    test "returns the job_runtime_environment when it is windows" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS")
    end

    test "returns the job_runtime_environment when it is macos" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "macos",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "MACOS")
    end

    test "returns the job_runtime_environment when it is macos_12_core" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "macos_12_core",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "MACOS_12_CORE")
    end

    test "returns the job_runtime_environment when it is macos_8_core" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "macos_8_core",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "MACOS_8_CORE")
    end

    test "returns the job_runtime_environment when it is macos_l" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "macos_l",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "MACOS_LARGE")
    end

    test "returns the job_runtime_environment when it is macos_xl" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "macos_xl",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "MACOS_XLARGE")
    end

    test "returns the job_runtime_environment when it is linux_4_core" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux_4_core",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU_4_CORE")
    end

    test "returns the job_runtime_environment when it is linux_8_core" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux_8_core",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU_8_CORE")
    end

    test "returns the job_runtime_environment when it is linux_16_core" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux_16_core",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU_16_CORE")
    end

    test "returns the job_runtime_environment when it is linux_32_core" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux_32_core",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU_32_CORE")
    end

    test "returns the job_runtime_environment when it is linux_64_core" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux_64_core",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU_64_CORE")
    end

    test "returns the job_runtime_environment when it is windows_4_core" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows_4_core",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS_4_CORE")
    end

    test "returns the job_runtime_environment when it is windows_8_core" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows_8_core",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS_8_CORE")
    end

    test "returns the job_runtime_environment when it is windows_16_core" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows_16_core",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS_16_CORE")
    end

    test "returns the job_runtime_environment when it is windows_32_core" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows_32_core",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS_32_CORE")
    end

    test "returns the job_runtime_environment when it is windows_64_core" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows_64_core",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS_64_CORE")
    end

    test "returns the job_runtime_environment when it is linux_2_core_arm" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux_2_core_arm",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU_2_CORE_ARM")
    end

    test "returns the job_runtime_environment when it is linux_4_core_arm" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux_4_core_arm",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU_4_CORE_ARM")
    end

    test "returns the job_runtime_environment when it is linux_8_core_arm" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux_8_core_arm",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU_8_CORE_ARM")
    end

    test "returns the job_runtime_environment when it is linux_16_core_arm" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux_16_core_arm",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU_16_CORE_ARM")
    end

    test "returns the job_runtime_environment when it is linux_32_core_arm" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux_32_core_arm",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU_32_CORE_ARM")
    end

    test "returns the job_runtime_environment when it is linux_64_core_arm" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux_64_core_arm",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU_64_CORE_ARM")
    end

    test "returns the job_runtime_environment when it is windows_2_core_arm" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows_2_core_arm",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS_2_CORE_ARM")
    end

    test "returns the job_runtime_environment when it is windows_4_core_arm" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows_4_core_arm",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS_4_CORE_ARM")
    end

    test "returns the job_runtime_environment when it is windows_8_core_arm" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows_8_core_arm",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS_8_CORE_ARM")
    end

    test "returns the job_runtime_environment when it is windows_16_core_arm" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows_16_core_arm",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS_16_CORE_ARM")
    end

    test "returns the job_runtime_environment when it is windows_32_core_arm" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows_32_core_arm",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS_32_CORE_ARM")
    end

    test "returns the job_runtime_environment when it is windows_64_core_arm" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows_64_core_arm",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS_64_CORE_ARM")
    end

    test "returns the job_runtime_environment when it is windows_4_core_gpu" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows_4_core_gpu",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS_4_CORE_GPU")
    end

    test "returns the job_runtime_environment when it is linux_4_core_gpu" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux_4_core_gpu",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU_4_CORE_GPU")
    end

    test "returns the job_runtime_environment when it is linux_2_core_advanced" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "linux_2_core_advanced",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "UBUNTU_2_CORE_ADVANCED")
    end

    test "returns the job_runtime_environment when it is windows_2_core_advanced" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows_2_core_advanced",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "WINDOWS_2_CORE_ADVANCED")
    end

    test "returns 'RUNTIME_UNKNOWN' when an invalid product sku name is provided" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "mystery-product-sku",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.job_runtime_environment, "RUNTIME_UNKNOWN")
    end
  end

  context "#check_run" do
    test "returns the check run associated to a line item" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        custom_fields: { "actions.check_run.id" => @check_run.id.to_s }
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.check_run, @check_run)
    end
  end

  context "#duration functions" do
    test "returns the duration in minutes" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        repository_id: @repo.id,
        quantity: 1,
        custom_fields: {
          "actions.check_run.id" => @check_run.id.to_s,
        }
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.duration_in_minutes, 1)
    end

    test "returns the effective duration in minutes" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows",
        repository_id: @repo.id,
        quantity: 1,
        effective_quantity: 2,
        custom_fields: {
          "actions.check_run.id" => @check_run.id.to_s,
        }
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.effective_duration_in_minutes, 2)
    end
  end

  context "workflow_id" do
    test "returns the workflow_id from a line item" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        custom_fields: {
          "actions.workflow.id" => "123",
        }
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.workflow_id, 123)
    end
  end

  context "check_run_id" do
    test "returns the check_run_id from a line item" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        custom_fields: {
          "actions.check_run.id" => @check_run.id.to_s,
        }
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.check_run_id, @check_run.id)
    end
  end

  context "end_time" do
    test "returns the end_time from a line item" do
      usage_at = (GitHub::Billing.today - 1.day).to_time
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        usage_at: Google::Protobuf::Timestamp.new(seconds: usage_at.to_i),
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Actions::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.end_time, usage_at.to_time.utc)
    end
  end
end
