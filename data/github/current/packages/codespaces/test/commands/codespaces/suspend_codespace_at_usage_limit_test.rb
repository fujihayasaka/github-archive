# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::SuspendCodespaceAtUsageLimitTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @user_in_organization = create(:user)
    @org.add_member(@user_in_organization)
    @suspendable_codespace_for_user = create(
      :codespace,
      billable_owner: @user,
      owner: @user
    )
    @suspendable_codespace_for_organization = create(
      :codespace,
      billable_owner: @org,
      owner: @user_in_organization
    )
    @failed_codespace_for_user = create(
      :codespace,
      :failed_in_vscs,
      billable_owner: @user,
      owner: @user
    )
  end

  setup do
    @disallow_spending_limit_result = Codespaces::Access::AllowedResult.new(
      Codespaces::Access::AllowedResult::DISALLOW_SPENDING_LIMIT
    )
    @disallow_entitlements_result = Codespaces::Access::AllowedResult.new(
      Codespaces::Access::AllowedResult::DISALLOW_ENTITLEMENTS
    )
    @allowed_spending_limit_result = Codespaces::Access::AllowedResult.new(
      Codespaces::Access::AllowedResult::ALLOWED
    )
    @disallow_machine_policy_result = Codespaces::Access::AllowedResult.new(
      Codespaces::Access::AllowedResult::DISALLOW_MACHINE_POLICY
    )
    @disallow_billing_result = Codespaces::Access::AllowedResult.new(
      Codespaces::Access::AllowedResult::DISALLOW_BILLING
    )
  end

  context "#call" do
    test "suspends codespace when a user's spending limit has been reached and codespace is suspendable" do
      Codespaces::AccessChecker.any_instance.stubs(:run_billing_check).returns(@disallow_spending_limit_result)

      Codespaces::LastKnownStopNoticeCache.expects(:mset).with(
        billable_owner_ids: [@user.id],
        notice: Codespaces::LastKnownStopNoticeCache::SPENDING_LIMIT_REACHED_FOR_USER
      )
      CodespacesSuspendEnvironmentJob.expects(:perform_later).with(
        codespace: @suspendable_codespace_for_user,
        suspension_reason: CodespacesSuspendEnvironmentJob::USAGE_LIMITS_REACHED_REASON
      )

      Codespaces::SuspendCodespaceAtUsageLimit.new(codespace: @suspendable_codespace_for_user).call
    end

    test "suspends codespace when an organization's spending limit has been reached and the codespace is suspendable" do
      Codespaces::AccessChecker.any_instance.stubs(:run_billing_check).returns(@disallow_spending_limit_result)

      CodespacesSuspendEnvironmentJob.expects(:perform_later).with(
        codespace: @suspendable_codespace_for_organization,
        suspension_reason: CodespacesSuspendEnvironmentJob::USAGE_LIMITS_REACHED_REASON
      )
      Codespaces::LastKnownStopNoticeCache.expects(:mset).with(
        billable_owner_ids: [@org.id],
        notice: Codespaces::LastKnownStopNoticeCache::SPENDING_LIMIT_REACHED_FOR_ORG
      )

      Codespaces::SuspendCodespaceAtUsageLimit.new(codespace: @suspendable_codespace_for_organization).call
    end

    test "suspends codespace when a user's entitlements have been reached and the codespace is suspendable" do
      Codespaces::AccessChecker.any_instance.stubs(:run_billing_check).returns(@disallow_entitlements_result)
      Codespaces::LastKnownStopNoticeCache.expects(:mset).with(
        billable_owner_ids: [@user.id],
        notice: Codespaces::LastKnownStopNoticeCache::ENTITLEMENTS_LIMIT_REACHED_FOR_USER
      )
      CodespacesSuspendEnvironmentJob.expects(:perform_later).with(
        codespace: @suspendable_codespace_for_user,
        suspension_reason: CodespacesSuspendEnvironmentJob::USAGE_LIMITS_REACHED_REASON
      )

      Codespaces::SuspendCodespaceAtUsageLimit.new(codespace: @suspendable_codespace_for_user).call
    end

    test "suspends codespace when a user can't be billed" do
      Codespaces::AccessChecker.any_instance.stubs(:run_billing_check).returns(@disallow_billing_result)
      Codespaces::LastKnownStopNoticeCache.expects(:mset).with(
        billable_owner_ids: [@user.id],
        notice: Codespaces::LastKnownStopNoticeCache::GENERIC_BILLING_ERROR_FOR_USER
      )
      CodespacesSuspendEnvironmentJob.expects(:perform_later).with(
        codespace: @suspendable_codespace_for_user,
        suspension_reason: CodespacesSuspendEnvironmentJob::USAGE_LIMITS_REACHED_REASON
      )

      Codespaces::SuspendCodespaceAtUsageLimit.new(codespace: @suspendable_codespace_for_user).call
    end

    test "suspends codespace when an org can't be billed" do
      Codespaces::AccessChecker.any_instance.stubs(:run_billing_check).returns(@disallow_billing_result)
      Codespaces::LastKnownStopNoticeCache.expects(:mset).with(
        billable_owner_ids: [@org.id],
        notice: Codespaces::LastKnownStopNoticeCache::GENERIC_BILLING_ERROR_FOR_ORG
      )
      CodespacesSuspendEnvironmentJob.expects(:perform_later).with(
        codespace: @suspendable_codespace_for_organization,
        suspension_reason: CodespacesSuspendEnvironmentJob::USAGE_LIMITS_REACHED_REASON
      )

      Codespaces::SuspendCodespaceAtUsageLimit.new(codespace: @suspendable_codespace_for_organization).call
    end

    test "does not suspend codespace when disallowed UsageChecker result is not billing related" do
      Codespaces::AccessChecker.any_instance.stubs(:calculate_allowed).returns(@disallow_machine_policy_result)

      Codespaces::LastKnownStopNoticeCache.expects(:mset).never
      CodespacesSuspendEnvironmentJob.expects(:perform_later).never

      Codespaces::SuspendCodespaceAtUsageLimit.new(codespace: @suspendable_codespace_for_user).call
    end

    test "returns early when codespace is not suspendable" do
      Codespaces::AccessChecker.any_instance.expects(:calculate_allowed).never

      Codespaces::LastKnownStopNoticeCache.expects(:mset).never
      CodespacesSuspendEnvironmentJob.expects(:perform_later).never

      Codespaces::SuspendCodespaceAtUsageLimit.new(codespace: @failed_codespace_for_user).call
    end
  end
end
