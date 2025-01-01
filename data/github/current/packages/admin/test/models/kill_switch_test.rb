# typed: true
# frozen_string_literal: true

require "test_helper"

class KillSwitchTest < GitHub::TestCase
  include KillSwitch
  include GitHub::LoggerHelper

  skip_enterprise

  fixtures do
    @workload_name = "Workload"

    @user = create :user
    @org = create :organization
    @business = create :business
  end

  setup do
    GitHub.flipper[:bypass_heavy_workloads].enable(@business)
    GitHub.flipper[:bypass_heavy_workloads].enable(@org)
  end

  if TestEnv.test_all_features?
    test "returns false in TEST_ALL_FEATURES CI" do
      refute @business.kill_switch_enabled?(@workload_name)
    end
  else
    context "business" do
      test "returns true with feature flag enabled" do
        assert @business.kill_switch_enabled?(@workload_name)
      end

      test "returns false without feature flag enabled" do
        GitHub.flipper[:bypass_heavy_workloads].disable
        refute @business.kill_switch_enabled?(@workload_name)
      end

      test "logs the skipped workload" do
        expected_keys = {
          "exception.type": "KillSwitch",
          "exception.message": "Workload skipped due to bypass_heavy_workloads flag",
          "workload": @workload_name,
          "gh.business.id": @business.id,
        }
        assert_logged(**expected_keys) do
          @business.kill_switch_enabled?(@workload_name)
        end
      end

      test "logs the skipped workload with extra log fields" do
        expected_keys = {
          "exception.type": "KillSwitch",
          "exception.message": "Workload skipped due to bypass_heavy_workloads flag",
          "workload": @workload_name,
          "gh.business.id": @business.id,
          "gh.user.id": 1,
        }
        assert_logged(**expected_keys) do
          @business.kill_switch_enabled?(@workload_name, log_fields: { "gh.user.id": 1 })
        end
      end
    end

    context "#organization" do
      test "returns true for org with feature flag enabled" do
        # assert @org.kill_switch_enabled?(@workload_name)
        assert @org.kill_switch_enabled?(@workload_name)
      end

      test "returns false without feature flag enabled" do
        GitHub.flipper[:bypass_heavy_workloads].disable
        refute @org.kill_switch_enabled?(@workload_name)
      end

      test "returns true if business is skipping heavy workloads" do
        business = create(:business, organizations: [@org])

        GitHub.flipper[:bypass_heavy_workloads].disable(@org)
        GitHub.flipper[:bypass_heavy_workloads].enable(business)

        @org.reload
        assert @org.kill_switch_enabled?(@workload_name)
      end

      test "logs the skipped workload" do
        expected_keys = {
          "exception.type": "KillSwitch",
          "exception.message": "Workload skipped due to bypass_heavy_workloads flag",
          "workload": @workload_name,
          "gh.organization.id": @org.id,
        }
        assert_logged(**expected_keys) do
          @org.kill_switch_enabled?(@workload_name)
        end
      end

      test "logs the skipped workload with extra fields logged" do
        expected_keys = {
          "exception.type": "KillSwitch",
          "exception.message": "Workload skipped due to bypass_heavy_workloads flag",
          "workload": @workload_name,
          "gh.organization.id": @org.id,
          "gh.user.id": 1,
        }
        assert_logged(**expected_keys) do
          @org.kill_switch_enabled?(@workload_name, log_fields: { "gh.user.id": 1 })
        end
      end

      test "logs the skipped workload with business context if skipped due to business" do
        business = create(:business, organizations: [@org])

        GitHub.flipper[:bypass_heavy_workloads].enable(business)

        @org.reload
        expected_keys = {
          "exception.type": "KillSwitch",
          "exception.message": "Workload skipped due to bypass_heavy_workloads flag",
          "workload": @workload_name,
          "gh.business.id": business.id,
          "gh.organization.id": @org.id,
          "gh.user.id": 1,
        }
        assert_logged(**expected_keys) do
          @org.kill_switch_enabled?(@workload_name, log_fields: { "gh.user.id": 1 })
        end
      end
    end
  end
end
