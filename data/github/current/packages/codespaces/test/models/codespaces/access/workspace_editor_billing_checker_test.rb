# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Access::WorkspaceEditorBillingCheckerTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    disable_feature_flag(:codespaces_hadron_no_limits, @user)
    @org = create(:credit_card_organization, plan: GitHub::Plan.business)
    @org.add_member(@user)
  end

  context "#perform" do
    test "returns allowed if monthly usage is less than allowed usage" do
      # Since the workspace editor billing checker uses "this month" as its
      # billing period, if these tests are run during the month switchover (from
      # October to November for example), they will likely fail and be flaky
      Timecop.freeze do
        create(:codespace_usage_record, :for_workspace_editor_cloud_environment, owner: @user, usage_seconds: Codespaces::Dials::WorkspaceEditorIndividualUsageLimitSeconds.new(force_cache_miss: true).value - 1)
        result = Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: @user, billable_owner: @user).perform
        assert result.allowed?
      end
    end

    test "returns disallowed if monthly usage is greater than or equal to allowed usage" do
      Timecop.freeze do
        create(:codespace_usage_record, :for_workspace_editor_cloud_environment, owner: @user, usage_seconds: Codespaces::Dials::WorkspaceEditorIndividualUsageLimitSeconds.new(force_cache_miss: true).value)
        result = Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: @user, billable_owner: @user).perform
        refute result.allowed?
      end
    end

    test "properly sums up multiple usage records when checking usage" do
      Timecop.freeze do
        set_monthly_usage_limit(20)
        create_list(:codespace_usage_record, 4, :for_workspace_editor_cloud_environment, owner: @user, usage_seconds: 5)
        result = Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: @user, billable_owner: @user).perform
        refute result.allowed?
      end
    end

    test "returns allowed if monthly usage is for normal codespaces" do
      Timecop.freeze do
        create(:codespace_usage_record, owner: @user, usage_seconds: Codespaces::Dials::WorkspaceEditorIndividualUsageLimitSeconds.new(force_cache_miss: true).value)
        result = Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: @user, billable_owner: @userr).perform
        assert result.allowed?
      end
    end

    test "returns allowed if user is in cwtp limit opt-out flag" do
      Timecop.freeze do
        enable_feature_flag(:codespaces_hadron_no_limits, @user)
        create(:codespace_usage_record, :for_workspace_editor_cloud_environment, owner: @user, usage_seconds: Codespaces::Dials::WorkspaceEditorIndividualUsageLimitSeconds.new(force_cache_miss: true).value)
        result = Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: @user, billable_owner: @user).perform
        assert result.allowed?
      end
    end

    test "returns allowed if billable owner is a copilot enterprise org" do
      Timecop.freeze do
        ::Copilot::Organization.any_instance.stubs(:can_use_copilot_enterprise_features?).returns(true)
        result = Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: @user, billable_owner: @user).perform
        assert result.allowed?
      end
    end

    test "ensures we check individual usage when the billable owner is a non-copilot org" do
      Timecop.freeze do
        create(:codespace_usage_record, :for_workspace_editor_cloud_environment, owner: @user, usage_seconds: Codespaces::Dials::WorkspaceEditorIndividualUsageLimitSeconds.new(force_cache_miss: true).value)
        ::Copilot::Organization.any_instance.stubs(:can_use_copilot_enterprise_features?).returns(false)
        result = Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: @user, billable_owner: @user).perform
        refute result.allowed?
      end
    end

    test "returns allowed if the user is under the limit but the billable_owner is nil" do
      Timecop.freeze do
        create(:codespace_usage_record, :for_workspace_editor_cloud_environment, owner: @user, usage_seconds: Codespaces::Dials::WorkspaceEditorIndividualUsageLimitSeconds.new(force_cache_miss: true).value - 1)
        result = Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: @user, billable_owner: nil).perform
        assert result.allowed?
      end
    end

    test "returns disallowed if the user is nil" do
      Timecop.freeze do
        result = Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: nil, billable_owner: nil).perform
        refute result.allowed?
      end
    end
  end

  context "#should_check?" do
    test "false if owner is nil" do
      refute Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: nil, billable_owner: @user).should_check?
    end

    test "false if billable owner is a copilot enterprise org" do
      ::Copilot::Organization.any_instance.stubs(:can_use_copilot_enterprise_features?).returns(true)
      refute Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: @user, billable_owner: @org).should_check?
    end

    test "false if owner is in hadron limit opt-out flag" do
      enable_feature_flag(:codespaces_hadron_no_limits, @user)
      refute Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: @user, billable_owner: @user).should_check?
    end

    test "true if flag is enabled, billable_owner is nil, and owner is not in workspace editor limit opt-out flag" do
      assert Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: @user, billable_owner: nil).should_check?
    end

    test "true if flag is enabled, billable_owner is not a copilot_interprise, and owner is not in workspace editor limit opt-out flag" do
      ::Copilot::Organization.any_instance.stubs(:can_use_copilot_enterprise_features?).returns(false)
      assert Codespaces::Access::WorkspaceEditorBillingChecker.new(owner: @user, billable_owner: @org).should_check?
    end
  end

  def set_monthly_usage_limit(value)
    dial = Codespaces::Dials::WorkspaceEditorIndividualUsageLimitSeconds.new(force_cache_miss: true)
    dial.value = value
    dial.save
  end
end
