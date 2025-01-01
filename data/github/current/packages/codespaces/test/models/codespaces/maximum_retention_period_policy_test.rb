# typed: true
# frozen_string_literal: true

require "test_helper"

class MaximumRetentionPeriodPolicyTest < GitHub::TestCase
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

  def assert_has_max_retention_period_policy_override(assert_true)
    result = Codespaces::MaximumRetentionPeriodPolicy.has_override?(@codespace_id)

    if assert_true
      assert result
    else
      refute result
    end
  end

  context "#get_applicable_retention_period" do
    context "org policy exists" do
      test "returns org retention policy when it is the lowest (org repo)" do
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 10.days.in_minutes.to_i, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD)
        create(:policy_constraint, policy_group: @policy_group_repo, maximum_value: 20.days.in_minutes.to_i, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD)
        @user.update_codespace_default_retention_period(25.days.in_minutes.to_i, actor: @user)

        result = Codespaces::MaximumRetentionPeriodPolicy.get_applicable_retention_period(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          requested_retention_period_minutes: 24.days.in_minutes.to_i,
          codespace_id: @codespace_id
        )

        assert_equal 10.days.in_minutes.to_i, result
        assert_has_max_retention_period_policy_override(true)
      end

      test "returns org retention policy when it is the lowest (fork of org repo)" do
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 10.days.in_minutes.to_i, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD)
        create(:policy_constraint, policy_group: @policy_group_repo, maximum_value: 20.days.in_minutes.to_i, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD)
        @user.update_codespace_default_retention_period(25.days.in_minutes.to_i, actor: @user)

        @org.allow_private_repository_forking(actor: @user)
        fork_repo = create(:fork_repository, forker: @user, fork_repo: @org_repo)

        result = Codespaces::MaximumRetentionPeriodPolicy.get_applicable_retention_period(
          user: @user,
          repository: fork_repo,
          billable_owner: @org,
          requested_retention_period_minutes: 24.days.in_minutes.to_i,
          codespace_id: @codespace_id
        )

        assert_equal 10.days.in_minutes.to_i, result
        assert_has_max_retention_period_policy_override(true)
      end

      test "returns user setting when it is the lowest and requested_retention_period_minutes is over the limit" do
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 10.days.in_minutes.to_i, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD)
        create(:policy_constraint, policy_group: @policy_group_repo, maximum_value: 20.days.in_minutes.to_i, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD)
        @user.update_codespace_default_retention_period(5.days.in_minutes.to_i, actor: @user)

        result = Codespaces::MaximumRetentionPeriodPolicy.get_applicable_retention_period(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          requested_retention_period_minutes: 35.days.in_minutes.to_i,
          codespace_id: @codespace_id
        )

        assert_equal 5.days.in_minutes.to_i, result
        assert_has_max_retention_period_policy_override(false)
      end

      test "returns requested_retention_period_minutes if it is within the limit even if user settings is lower" do
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 10.days.in_minutes.to_i, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD)
        create(:policy_constraint, policy_group: @policy_group_repo, maximum_value: 20.days.in_minutes.to_i, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD)
        @user.update_codespace_default_retention_period(1.day.in_minutes.to_i, actor: @user)

        result = Codespaces::MaximumRetentionPeriodPolicy.get_applicable_retention_period(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          requested_retention_period_minutes: 5.days.in_minutes.to_i,
          codespace_id: @codespace_id
        )

        assert_equal 5.days.in_minutes.to_i, result
        assert_has_max_retention_period_policy_override(false)
      end

      test "returns requested_retention_period_minutes when it is the lowest" do
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 10.days.in_minutes.to_i, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD)
        create(:policy_constraint, policy_group: @policy_group_repo, maximum_value: 20.days.in_minutes.to_i, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD)
        @user.update_codespace_default_retention_period(5.days.in_minutes.to_i, actor: @user)

        result = Codespaces::MaximumRetentionPeriodPolicy.get_applicable_retention_period(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          requested_retention_period_minutes: 2.days.in_minutes.to_i,
          codespace_id: @codespace_id
        )

        assert_equal 2.days.in_minutes.to_i, result
        assert_has_max_retention_period_policy_override(false)
      end
    end

    context "org policy does not exist" do
      test "returns requested_retention_period_minutes if present" do
        @user.update_codespace_default_retention_period(2.days.in_minutes.to_i, actor: @user)

        result = Codespaces::MaximumRetentionPeriodPolicy.get_applicable_retention_period(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          requested_retention_period_minutes: 3.days.in_minutes.to_i,
          codespace_id: @codespace_id
        )

        assert_equal 3.days.in_minutes.to_i, result
        assert_has_max_retention_period_policy_override(false)
      end

      test "returns user setting if requested_retention_period_minutes is not present" do
        @user.update_codespace_default_retention_period(2.days.in_minutes.to_i, actor: @user)

        result = Codespaces::MaximumRetentionPeriodPolicy.get_applicable_retention_period(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          codespace_id: @codespace_id
        )

        assert_equal 2.days.in_minutes.to_i, result
        assert_has_max_retention_period_policy_override(false)
      end

      test "defaults to Codespace::MAX_RETENTION_PERIOD if user setting is nil && FF enabled " do
        result = Codespaces::MaximumRetentionPeriodPolicy.get_applicable_retention_period(
          user: @user,
          repository: @org_repo,
          billable_owner: @org,
          codespace_id: @codespace_id
        )

        assert_equal Codespace::MAX_RETENTION_PERIOD, result
        assert_has_max_retention_period_policy_override(false)
      end
    end

    context "billable owner is not an org" do
      test "returns requested_retention_period_minutes if present" do
        @user.update_codespace_default_retention_period(2.days.in_minutes.to_i, actor: @user)

        result = Codespaces::MaximumRetentionPeriodPolicy.get_applicable_retention_period(
          user: @user,
          repository: @org_repo,
          billable_owner: @user,
          requested_retention_period_minutes: 3.days.in_minutes.to_i
        )

        assert_equal 3.days.in_minutes.to_i, result
      end

      test "returns user setting if requested_retention_period_minutes is not present" do
        @user.update_codespace_default_retention_period(2.days.in_minutes.to_i, actor: @user)

        result = Codespaces::MaximumRetentionPeriodPolicy.get_applicable_retention_period(
          user: @user,
          repository: @org_repo,
          billable_owner: @user,
          codespace_id: @codespace_id
        )

        assert_equal 2.days.in_minutes.to_i, result
        assert_has_max_retention_period_policy_override(false)
      end

      test "Codespace::MAX_RETENTION_PERIOD if user setting is nil" do
        result = Codespaces::MaximumRetentionPeriodPolicy.get_applicable_retention_period(
          user: @user,
          repository: @org_repo,
          billable_owner: @user
        )

        assert_equal Codespace::MAX_RETENTION_PERIOD, result
      end
    end
  end

  context "#retention_period_notice" do
    test "returns notice message" do
      msg = Codespaces::MaximumRetentionPeriodPolicy.retention_period_notice(10)
      assert_equal "Retention period for this codespace is set to 10 minutes in compliance with your organization's policy", msg
    end

    test "returns notice message with days" do
      msg = Codespaces::MaximumRetentionPeriodPolicy.retention_period_notice(1500)
      assert_equal "Retention period for this codespace is set to 1 day in compliance with your organization's policy", msg
    end

    test "returns empty string when not given auto_shutdown_delay_minutes" do
      msg = Codespaces::MaximumRetentionPeriodPolicy.retention_period_notice(nil)
      assert_empty msg
    end
  end

end unless GitHub.enterprise?
