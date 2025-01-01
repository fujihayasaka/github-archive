# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class ProcessPlanChangeTest < GitHub::TestCase
    fixtures do
      @org = create(:codespaces_organization, name: "test-billable-org", plan: GitHub::Plan.business)
      @user = @org.admin
      @org_repo = create(:repository, owner: @org)
      Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

      @codespaces = create_list(:codespace, 3, billable_owner: @org, repository: @org_repo, owner: @user)
      disable_feature_flag(:codespaces_billing_free)

      @jobs = [
        Codespaces::SuspendDependentCodespacesJob,
        CodespacesSuspendEnvironmentJob,
        CodespacesProcessSystemEventJob
      ]
    end

    context "org downgrade from paid to free plan", skip_enterprise: true do
      test "org plan downgrade to free enqueues job to process system ", skip_enterprise: true do
        organization = create(:codespaces_organization, plan: GitHub::Plan.business_plus)
        user = create(:user)
        organization.add_member(user)
        repository = create(:repository, owner: organization)
        codespace = create(:codespace, repository: repository, owner: user)

        change_plan(organization, GitHub::Plan.free)

        assert_enqueued_with(job: CodespacesProcessSystemEventJob, args: [{ codespaces: [codespace], transfer_billable_owner: false, deletion_reason: Codespace.deletion_reasons[:org_downgrade] }])
      end

      test "org plan downgrade to free stops and disables org-billed codespaces", skip_enterprise: true do
        FakeVSOServer.reset!
        @codespaces.each do |codespace|
          FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::AVAILABLE }
        end

        assert_empty FakeVSOServer.environments_shutdown

        perform_enqueued_jobs(only: @jobs) do
          change_plan(@org, GitHub::Plan.free)
        end

        @codespaces.each do |codespace|
          assert FakeVSOServer.environments_shutdown.find { |e| e["id"] == codespace.guid }.present?
          assert Codespace.find(codespace.id)
          refute Codespace.find(codespace.id).accessible?
        end
      end

      test "makes codespaces inaccessible and soft-deletes them in 7 days" do
        perform_enqueued_jobs(only: @jobs) do
          Codespaces::TransferBillableOwner.expects(:call).never
          @codespaces.each do |codespace|
            Codespaces::CleanUpInaccessibleJob.expects(:perform_after_waiting_period).with(waiting_period: Codespaces::ProcessSystemEvent::CLEAN_UP_INACCESSIBLE_CODESPACE_WAITING_PERIOD, codespace: codespace, reason: Codespace.deletion_reasons[:org_downgrade])
            CodespacesSuspendEnvironmentJob.expects(:perform_later).with(codespace: codespace, ignore_deleted: true)
          end

          change_plan(@org, GitHub::Plan.free)

          @codespaces.each do |codespace|
            refute codespace.reload.accessible?
            assert_equal @org, codespace.billable_owner
          end
        end
      end

      test "stops billing codespaces for storage" do
        change_plan(@org, GitHub::Plan.free)

        @codespaces.each do |codespace|
          billing_data = create_billing_data(codespace.owner, codespace: codespace)
          billing_entry = billing_data[:billing_entry]
          billing_message = billing_data[:billing_message]
          tracked_usage = billing_data[:tracked_usage]

          refute Codespaces::Billing::StorageMeuseMessageHandler.new(billing_message: billing_message, tracked_usage: tracked_usage, billing_entry: billing_entry).send(:should_publish?)
        end
      end

      test "no other automated clean ups will delete codespaces disabled by org downgrade" do
        perform_enqueued_jobs(only: @jobs) do
          Codespaces::TransferBillableOwner.expects(:call).never
          @codespaces.each do |codespace|
            Codespaces::CleanUpInaccessibleJob.expects(:perform_after_waiting_period).with(waiting_period: Codespaces::ProcessSystemEvent::CLEAN_UP_INACCESSIBLE_CODESPACE_WAITING_PERIOD, codespace: codespace, reason: Codespace.deletion_reasons[:org_downgrade])
            CodespacesSuspendEnvironmentJob.expects(:perform_later).with(codespace: codespace, ignore_deleted: true)
          end

          change_plan(@org, GitHub::Plan.free)
        end

        Codespaces::PurgeSoftDeletedCodespacesJob.perform_now
        Codespaces::PastRetentionJob.perform_now

        @codespaces.each do |codespace|
          assert codespace.reload.present?
          refute codespace.is_deleted?
          refute codespace.accessible?
        end
      end

      test "user downgrading to free isn't subject to the same rules as orgs", skip_enterprise: true do
        user = create(:user)

        assert_no_enqueued_jobs do
          Codespaces::ProcessPlanChange.call(
            user_id: user.id,
            old_plan_name: "pro",
            new_plan_name: "free"
          )
        end
      end

      test "no errors and no jobs enqueued if the organization has been deleted", skip_enterprise: true do
        assert_no_enqueued_jobs do
          Codespaces::ProcessPlanChange.call(
            user_id: -1,
            old_plan_name: "pro",
            new_plan_name: "free"
          )
        end
      end

      test "job to notify org admins is enqued on downgrade", skip_enterprise: true do
        organization = create(:codespaces_organization, plan: GitHub::Plan.business_plus)
        user = create(:user)
        organization.add_member(user)
        repository = create(:repository, owner: organization)
        codespace = create(:codespace, repository: repository, owner: user)
        Timecop.freeze do
          deletion_date = Codespaces::ProcessSystemEvent::CLEAN_UP_INACCESSIBLE_CODESPACE_WAITING_PERIOD.from_now
          change_plan(organization, GitHub::Plan.free)

          assert_enqueued_with(job: Codespaces::OrgDowngradeCleanupNotificationJob, args: [{ owner_id: organization.id, deletion_date: deletion_date }])
        end
      end

      test "appropriate deletion reason is specified when cleaning up codespaces after org downgrade", skip_enterprise: true do
        organization = create(:codespaces_organization, plan: GitHub::Plan.business_plus)
        user = create(:user)
        organization.add_member(user)
        repository = create(:repository, owner: organization)
        codespace = create(:codespace, repository: repository, owner: user)

        change_plan(organization, GitHub::Plan.free)

        assert_enqueued_with(job: CodespacesProcessSystemEventJob, args: [{ codespaces: [codespace], transfer_billable_owner: false, deletion_reason: Codespace.deletion_reasons[:org_downgrade] }])
      end
    end

    context "org upgrades back to paid plan", skip_enterprise: true do
      test "makes codespaces accessible again" do
        change_plan(@org, GitHub::Plan.free)
        @codespaces.each do |codespace|
          refute codespace.reload.accessible?
        end

        change_plan(@org, GitHub::Plan.business)
        @codespaces.each do |codespace|
          assert codespace.reload.accessible?
        end
      end
    end

    context "irrelevant plan changes", skip_enterprise: true do
      test "org plan switched to any other plan but free leaves codespaces untouched", skip_enterprise: true do
        organization = create(:codespaces_organization, plan: GitHub::Plan.business_plus)

        assert_no_enqueued_jobs do
          Codespaces::ProcessPlanChange.call(
            user_id: organization.id,
            old_plan_name: "business",
            new_plan_name: "business_plus"
          )
        end
      end

      test "org plan details changed but plan itself is the same leaves codespaces", skip_enterprise: true do
        organization = create(:codespaces_organization, plan: GitHub::Plan.business_plus)

        assert_no_enqueued_jobs do
          Codespaces::ProcessPlanChange.call(
            user_id: organization.id,
            old_plan_name: "business",
            new_plan_name: "business"
          )
        end
      end
    end

    private

    def change_plan(org, plan)
      org.pending_plan_changes.create!(
        active_on: Time.now,
        plan: plan,
        actor: org.admin,
      ).run
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
      tracked_usage = billing_message.tracked_usages_for(billing_entry.codespace_guid).find(&:is_storage?)
      { billing_message:, billing_entry:, tracked_usage: }
    end
  end
end
