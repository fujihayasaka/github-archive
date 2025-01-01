# typed: true
# frozen_string_literal: true

require "test_helper"

class MaximumIdleTimeoutPolicyTest < GitHub::TestCase
  include CodespacesPlanFixtures
  fixtures do
    @user = create(:user)

    @user_repo = create(:repository, owner: @user)

    @org = create(:codespaces_organization, admin: @user)
    @org.add_member(@user)
    @org_repo = create(:private_repository, owner: @org)
    @org_repo.add_member(@user)
    Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

    @policy_group_org = create(:policy_group, owner: @org, name: "all repos")
    @policy_group_repo = create(:policy_group, owner: @org, name: "specific repo")
    create(:policy_group_membership, policy_group: @policy_group_org, target: @org)
    create(:policy_group_membership, policy_group: @policy_group_repo, target: @org_repo)

    @codespace_id = 1
  end

  def assert_has_max_idle_timeout_policy_override(assert_true)
    result = Codespaces::MaximumIdleTimeoutPolicy.has_override?(@codespace_id)

    if assert_true
      assert result
    else
      refute result
    end
  end

  context "#get_applicable_idle_timeout" do
    context "org policy exists" do
      test "returns org idle timeout when it is the lowest (org repo)" do
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 60, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        create(:policy_constraint, policy_group: @policy_group_repo, maximum_value: 120, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        @user.update_codespace_default_idle_timeout(200, actor: @user)

        result = Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          requested_idle_timeout_minutes: 240,
          codespace_id: @codespace_id
        )

        assert_equal 60, result
        assert_has_max_idle_timeout_policy_override(true)
      end

      test "returns org idle timeout when it is the lowest (fork of org repo)" do
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 60, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        create(:policy_constraint, policy_group: @policy_group_repo, maximum_value: 120, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        @user.update_codespace_default_idle_timeout(200, actor: @user)

        @org.allow_private_repository_forking(actor: @user)
        fork_repo = create(:fork_repository, forker: @user, fork_repo: @org_repo)

        result = Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: fork_repo,
          billable_owner: @org,
          requested_idle_timeout_minutes: 240,
          codespace_id: @codespace_id
        )

        assert_equal 60, result
        assert_has_max_idle_timeout_policy_override(true)
      end

      test "returns org idle timeout when it is the lowest and doesn't set assert_has_max_idle_timeout_policy_override when codespace_id is nil" do
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 60, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        create(:policy_constraint, policy_group: @policy_group_repo, maximum_value: 120, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        @user.update_codespace_default_idle_timeout(200, actor: @user)

        result = Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          requested_idle_timeout_minutes: 240
        )

        assert_equal 60, result
        assert_has_max_idle_timeout_policy_override(false)
      end

      test "returns user setting when it is the lowest and requested_idle_timeout_minutes is over the limit" do
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 60, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        create(:policy_constraint, policy_group: @policy_group_repo, maximum_value: 120, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        @user.update_codespace_default_idle_timeout(30, actor: @user)

        result = Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          requested_idle_timeout_minutes: 240,
          codespace_id: @codespace_id
        )

        assert_equal 30, result
        assert_has_max_idle_timeout_policy_override(false)
      end

      test "returns requested_idle_timeout_minutes if it is within the limit even if user settings is lower" do
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 80, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        create(:policy_constraint, policy_group: @policy_group_repo, maximum_value: 60, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        @user.update_codespace_default_idle_timeout(30, actor: @user)

        result = Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          requested_idle_timeout_minutes: 40,
          codespace_id: @codespace_id
        )

        assert_equal 40, result
        assert_has_max_idle_timeout_policy_override(false)
      end

      test "returns requested_idle_timeout_minutes if it is within the limit even if user settings is lower and deletes has_max_idle_timeout_policy_override key" do
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 80, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        create(:policy_constraint, policy_group: @policy_group_repo, maximum_value: 60, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        @user.update_codespace_default_idle_timeout(30, actor: @user)
        Codespaces::MaximumIdleTimeoutPolicy.set_has_override_key!(@codespace_id)

        Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          requested_idle_timeout_minutes: 40,
          codespace_id: @codespace_id
        )

        assert_has_max_idle_timeout_policy_override(false)
      end

      test "returns requested_idle_timeout_minutes when it is the lowest" do
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 60, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        create(:policy_constraint, policy_group: @policy_group_repo, maximum_value: 120, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)
        @user.update_codespace_default_idle_timeout(200, actor: @user)

        result = Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          requested_idle_timeout_minutes: 40,
          codespace_id: @codespace_id
        )

        assert_equal 40, result
        assert_has_max_idle_timeout_policy_override(false)
      end
    end

    context "org policy does not exist" do
      test "deletes has_max_idle_timeout_policy_override key" do
        @user.update_codespace_default_idle_timeout(200, actor: @user)
        Codespaces::MaximumIdleTimeoutPolicy.set_has_override_key!(@codespace_id)

        Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          requested_idle_timeout_minutes: 240,
          codespace_id: @codespace_id
        )

        assert_has_max_idle_timeout_policy_override(false)
      end

      test "returns requested_idle_timeout_minutes if present" do
        @user.update_codespace_default_idle_timeout(200, actor: @user)

        result = Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          requested_idle_timeout_minutes: 240,
          codespace_id: @codespace_id
        )

        assert_equal 240, result
        assert_has_max_idle_timeout_policy_override(false)
      end

      test "returns user setting if requested_idle_timeout_minutes is not present" do
        @user.update_codespace_default_idle_timeout(200, actor: @user)

        result = Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          codespace_id: @codespace_id
        )

        assert_equal 200, result
        assert_has_max_idle_timeout_policy_override(false)
      end

      test "Codespaces::VscsClient::AUTO_SHUTDOWN_MINUTES if user setting is nil" do
        result = Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          codespace_id: @codespace_id
        )

        assert_equal Codespaces::VscsClient::AUTO_SHUTDOWN_MINUTES, result
        assert_has_max_idle_timeout_policy_override(false)
      end
    end

    context "billable owner is not an org" do
      test "deletes has_max_idle_timeout_policy_override key" do
        @user.update_codespace_default_idle_timeout(200, actor: @user)
        Codespaces::MaximumIdleTimeoutPolicy.set_has_override_key!(@codespace_id)

        Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @user,
          requested_idle_timeout_minutes: 240,
          codespace_id: @codespace_id
        )

        assert_has_max_idle_timeout_policy_override(false)
      end

      test "returns requested_idle_timeout_minutes if present" do
        @user.update_codespace_default_idle_timeout(200, actor: @user)

        result = Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @user,
          requested_idle_timeout_minutes: 240,
          codespace_id: @codespace_id
        )

        assert_equal 240, result
        assert_has_max_idle_timeout_policy_override(false)
      end

      test "returns user setting if requested_idle_timeout_minutes is not present" do
        @user.update_codespace_default_idle_timeout(200, actor: @user)

        result = Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @user,
          codespace_id: @codespace_id
        )

        assert_equal 200, result
        assert_has_max_idle_timeout_policy_override(false)
      end

      test "Codespaces::VscsClient::AUTO_SHUTDOWN_MINUTES if user setting is nil" do
        result = Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
          user: @user,
          repository: @org_repo,
          billable_owner: @user,
          codespace_id: @codespace_id
        )

        assert_equal Codespaces::VscsClient::AUTO_SHUTDOWN_MINUTES, result
        assert_has_max_idle_timeout_policy_override(false)
      end
    end
  end

  context "#idle_timeout_notice" do
    test "returns notice message" do
      msg = Codespaces::MaximumIdleTimeoutPolicy.idle_timeout_notice(10)
      assert_equal "Idle timeout for this codespace is set to 10 minutes in compliance with your organization's policy", msg
    end

    test "returns empty string when not given auto_shutdown_delay_minutes" do
      msg = Codespaces::MaximumIdleTimeoutPolicy.idle_timeout_notice(nil)
      assert_empty msg
    end
  end
end unless GitHub.enterprise?
