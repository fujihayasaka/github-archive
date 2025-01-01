# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::UpdateSettingsTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "user")

    @org = create(:codespaces_organization, admin: @user, plan: GitHub::Plan.business)
    @org.add_member(@user)
    @org_repo = create(:private_repository, owner: @org)
    @org_repo.add_member(@user)

    # Make a org-billable codespace for broader SKU access
    @codespace = create(:codespace, owner: @user, repository: @org_repo, sku_name: "standardLinux32gb")
  end

  setup_once do
    enable_cache_storage
  end

  setup do
    reset_cache
    reset_monolith_redis_rate_limiter
  end

  teardown_once do
    disable_cache_storage
  end

  context "updating sku_name across the same storage size" do
    test "allows setting sku" do
      events = subscribe "codespaces.change_sku"
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].enable
      basic = "basicLinux32gb"
      premium = "premiumLinux32gb"

      expected_payload = {
        codespace_id: @codespace.id,
        environment_id: @codespace.guid,
        new_sku: basic,
        old_sku: @codespace.sku_name,
        plan_id: @codespace.plan_id,
        user: @codespace.owner.login,
        user_id: @codespace.owner.id,
        repo: @codespace.repository.nwo,
        repo_id: @codespace.repository.id,
        public_repo: @codespace.repository.public?,
      }

      Codespaces::UpdateSettings.call(codespace: @codespace, sku_name: basic)

      assert_equal basic, @codespace.sku_name

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload

      Codespaces::UpdateSettings.call(codespace: @codespace, sku_name: premium)
      assert_equal premium, @codespace.sku_name

      expected_payload = {
        codespace_id: @codespace.id,
        environment_id: @codespace.guid,
        new_sku: premium,
        old_sku: basic,
        plan_id: @codespace.plan_id,
        user: @codespace.owner.login,
        user_id: @codespace.owner.id,
        repo: @codespace.repository.nwo,
        repo_id: @codespace.repository.id,
        public_repo: @codespace.repository.public?,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "rejects invalid sku names" do
      assert_raises(Codespaces::UpdateSettings::FailedToUpdate) do
        Codespaces::UpdateSettings.call(codespace: @codespace, sku_name: "pdp-11")
      end
    end

    test "respects feature flags" do
      GitHub.flipper[:codespaces_automated_testing].disable
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].disable

      sku = "premiumLinux32gb"
      assert_raises(Codespaces::UpdateSettings::FailedToUpdate) do
        Codespaces::UpdateSettings.call(codespace: @codespace, sku_name: sku)
      end

      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].enable
      Codespaces::UpdateSettings.call(codespace: @codespace, sku_name: sku)
      assert_equal sku, @codespace.sku_name
    end

    test "disallows SKU changes during provisioning" do
      codespace = create(:codespace, :provisioning, owner: @user)

      assert_raises(Codespaces::UpdateSettings::CodespacesStillProvisioningError) do
        Codespaces::UpdateSettings.call(codespace: codespace, sku_name: "premiumLinux")
      end
    end
  end

  context "updating sku_name across different storage sizes" do
    test "schedules an async job for storage transitions" do
      GitHub.flipper[Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG].enable

      CodespacesResizeStorageJob.expects(:perform_later)

      Codespaces::UpdateSettings.call(codespace: @codespace, sku_name: "standardLinux")
    end

    test "creates Codespaces::AsyncOperation to track the storage update operation" do
      GitHub.flipper[Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG].enable
      assert_difference "Codespaces::AsyncOperation.count", 1 do
        Codespaces::UpdateSettings.call(codespace: @codespace, sku_name: "standardLinux")
      end
    end

    test "codespace has a pending operation after receiveing a storage sku update" do
      GitHub.flipper[Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG].enable
      Codespaces::UpdateSettings.call(codespace: @codespace, sku_name: "standardLinux")

      assert @codespace.pending_async_operations.any?
    end
  end

  context "display name" do
    test "updating" do
      codespace = create(:codespace, display_name: "old name")
      Codespaces::UpdateSettings.call(codespace: codespace, display_name: "new name")
      assert_equal "new name", codespace.reload.display_name
    end

    test "fails if the name is too long" do
      codespace = create(:codespace, display_name: "old name")

      assert_raises(Codespaces::UpdateSettings::FailedToUpdate) do
        Codespaces::UpdateSettings.call(codespace: codespace, display_name: "codspaces" * 100)
      end
    end
  end

  context "retention period" do
    test "updating it from the default to 90min" do
      codespace = create(:codespace, retention_period_minutes: Codespace::MAX_RETENTION_PERIOD)
      Codespaces::UpdateSettings.call(codespace: codespace, retention_period_minutes: 90)
      assert_equal 90, codespace.reload.retention_period_minutes
    end

    test "updating it from 90min to the default" do
      codespace = create(:codespace, retention_period_minutes: 90)
      Codespaces::UpdateSettings.call(codespace: codespace, retention_period_minutes: nil)
      assert_equal Codespace::MAX_RETENTION_PERIOD, codespace.reload.retention_period_minutes
    end

    test "updating it from 90min to a value out of range" do
      codespace = create(:codespace, retention_period_minutes: 90)
      assert_raises(Codespaces::UpdateSettings::FailedToUpdate) do
        Codespaces::UpdateSettings.call(codespace: codespace, retention_period_minutes: 2.months.in_minutes)
      end
    end

    test "updating it from 90min to a value out of range for the org policy" do
      policy_group_org = create(:policy_group, owner: @org, name: "all repos")
      create(:policy_group_membership, policy_group: policy_group_org, target: @org)
      create(:policy_constraint, policy_group: policy_group_org,
             maximum_value: 1.day.in_minutes.to_i,
             allowed_values: nil,
             name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD)
      codespace = create(:codespace, retention_period_minutes: 90, owner: @user, billable_owner: @org, repository: @org_repo)
      Codespaces::UpdateSettings.call(codespace: codespace, retention_period_minutes: 2.days.in_minutes.to_i)
      # The max from the policy is 1 day (1440 minutes), so it uses that instead of the requested 90min
      assert_equal 1.day.in_minutes.to_i, codespace.reload.retention_period_minutes
    end
  end

  test "is rate limited" do
    GitHub.flipper[:codespaces_automated_testing].disable
    GitHub.flipper[:codespaces_bypass_rate_limiting].disable

    codespace = create(:codespace, display_name: "old name")
    GitHub.stub(:codespaces_per_minute_rate_limit, 0) do
      Timecop.freeze do
        assert_raises Codespaces::RateLimitError do
          Codespaces::UpdateSettings.call(codespace: codespace, display_name: "new name")
        end
      end
    end
  end

  test "update recent folders" do
    codespace = create(:codespace)
    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::AVAILABLE }

    Codespaces::UpdateSettings.call(codespace: codespace, recent_folders: Array.[]("path-1"))
    assert_equal ["path-1"], codespace.environment_data.recent_folders

    Codespaces::UpdateSettings.call(codespace: codespace, recent_folders: Array.[]("path-1", "path-2"))
    assert_equal %w[path-1 path-2], codespace.environment_data.recent_folders

    Codespaces::UpdateSettings.call(codespace: codespace, recent_folders: Array.[])
    assert_equal [], codespace.environment_data.recent_folders

    assert_raises Codespaces::UpdateSettings::FailedToUpdate do
      Codespaces::UpdateSettings.call(codespace: codespace, recent_folders: Array.[](""))
    end

    assert_raises Codespaces::UpdateSettings::FailedToUpdate do
      Codespaces::UpdateSettings.call(codespace: codespace, recent_folders: Array.[]("one", 2))
    end

    assert_raises Codespaces::UpdateSettings::FailedToUpdate do
      Codespaces::UpdateSettings.call(codespace: codespace, recent_folders: "folders")
    end

  end

  test "raises an exception when updating a codespace with a pending async operation" do
    create(:codespaces_async_operation, codespace: @codespace)
    assert_raises(Codespaces::AsyncOperation::PendingError) do
      Codespaces::UpdateSettings.call(codespace: @codespace, sku_name: "basicLinux32gb")
    end
  end
end unless GitHub.enterprise?
