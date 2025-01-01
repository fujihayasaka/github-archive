# typed: true
# frozen_string_literal: true

require "test_helper"
require File.join(Rails.root, "packages/repositories/test/jobs/legacy_remove_org_member_data_common_tests")

class RemoveOrgMemberForksJobTest < GitHub::TestCase
  include LegacyRemoveOrgMemberDataCommonTests

  fixtures do
    @restorable_org_user = create :restorable_organization_user
    @org = @restorable_org_user.organization
    @owner = @org.admin
    @org.allow_private_repository_forking(actor: @owner)
    @user = @restorable_org_user.user
    @repo = create :private_repository, owner: @org
    @owner_fork, reason = @repo.fork(forker: @owner)
    @org.add_member(@user)
    @user_fork, reason = @repo.fork(forker: @user)

    # Organization#remove_member! calls RemoveOrgMemberForks. To revoke the
    # member's abilities on the org without running the job under test we
    # supply only the relevant job name to inline:
    perform_enqueued_jobs(only: RevokeOrgMembershipAbilitiesJob) do
      @org.remove_member!(@user, save_settings: false)
    end
    @job_args = { "organization_id" => @org.id, "user_id" => @user.id }
  end

  test "Archives fork for removed member" do
    assert_difference("Repository.active.count", -1) do
      RemoveOrgMemberForksJob.perform_now(@job_args)
      RemoveOrgMemberForksJob.perform_now(@job_args)
    end
  end

  test "Does not archive fork for non removed member" do
    assert_difference("Repository.count", 0) do
      RemoveOrgMemberForksJob.perform_now("organization_id" => @org, "user_id" => @owner)
    end
  end

  test "Creates restorable records for removed forks" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not create restorables
    assert_difference("Restorable::Repository.count", 1) do
      RemoveOrgMemberForksJob.perform_now(@job_args)
    end
    assert_equal T.must(Restorable::Repository.last).archived_repository_id, @user_fork.id
  end

  test "Does not create restorable for public forks" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not create restorables
    @public_repo = create :repository, owner: @org
    @user_public_fork, reason = @public_repo.fork(forker: @user)

    assert_difference("Restorable::Repository.count", 1) do
      RemoveOrgMemberForksJob.perform_now(@job_args)
    end
    assert_equal T.must(Restorable::Repository.last).archived_repository_id, @user_fork.id
  end

  test "Does not create restorable for private forks not belonging to org" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not create restorables
    @private_repo = create :private_repository, owner: create(:user, plan: :medium)
    @private_repo.add_member(@user)
    @user_private_fork, reason = @private_repo.fork(forker: @user)

    assert_difference("Restorable::Repository.count", 1) do
      RemoveOrgMemberForksJob.perform_now(@job_args)
    end
    assert_equal T.must(Restorable::Repository.last).archived_repository_id, @user_fork.id
  end

  test "if there is no restorable user it does not create Restorable::Repository record" do
    assert_difference("Restorable::Repository.count", 0) do
      RemoveOrgMemberForksJob.perform_now(
        "organization_id" => @org.id,
        "user_id" => create(:user).id,
      )
    end
  end

  test "sends an email to the fork owner" do
    mailer_stub = stub("repo mailer")
    mailer_stub.expects(:deliver_later).once
    RepositoryMailer.expects(:private_fork_deleted).once.returns(mailer_stub)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      RemoveOrgMemberForksJob.perform_now(@job_args)
    end
  end

  test "is idempotent" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not create restorables
    assert_difference("Restorable::Repository.count", 1) do
      RemoveOrgMemberForksJob.perform_now(@job_args)
      RemoveOrgMemberForksJob.perform_now(@job_args)
    end
    assert_equal @user_fork.id, T.must(Restorable::Repository.last).archived_repository_id
  end

  test "retries the job if a throttling error occurs" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not create restorables
    verify_throttling(RemoveOrgMemberForksJob, @job_args)
  end

  context "handles exceptions and error cases, and signals Failbot when one occurs" do
    test "finishes successfully and does not call Failbot if each repo has a valid RepositoryNetwork" do
      verify_no_failbot_calls_by_default(RemoveOrgMemberForksJob, @org, @job_args)
    end

    test "calls via #pullable_by_user_or_no_plan_owner? and finishes running without raising any uncaught exceptions" do
      GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not leverage Failbot
      # Uses #pullable_by_user_or_no_plan_owner? to handle exceptions from a bad RepositoryNetwork on any repos
      perform_bad_network_test(RemoveOrgMemberForksJob, @org, @job_args)
    end
  end

  test "creates repo.destroy audit event with no actor" do
    repo_destroy_events = subscribe("repo.destroy")
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      RemoveOrgMemberForksJob.perform_now(@job_args)
    end
    assert_equal 1, repo_destroy_events.count
    assert destroy_event = repo_destroy_events.pop, "an event was expected"
    assert_nil destroy_event.payload[:actor]
  end
end
