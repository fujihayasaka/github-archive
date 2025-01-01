# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class NotifyPullRequestCommitChecksUpdatedJobTest < GitHub::TestCase
  include JobTestHelper
  include PullRequestIntegrationTestHelpers

  fixtures do
    @user = create(:user, plan: "pro")
    @repo = create(:repository, name: "hello-world", owner: @user, from_example: :rebase_pull_request)

    commit = @repo.heads.find("contrib").append_commit({ message: "blah", committer: @user }, @user) do |files|
      files.add("foo", "asdf")
    end
    @sha = commit.oid
  end

  def create_pr(user, head_sha)
    create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      user: user,
      head_sha:
    )
  end

  test "it triggers a subscription for pull requests with a matching head sha", skip_enterprise: true do
    pull = create_pr(@user, @sha)

    Platform::Schema.subscriptions.expects(:trigger).once.with(
      :pull_request_info_for_list_view_updated,
      { id: pull.global_relay_id },
      object: { commit_checks_updated: true }
    )
    NotifyPullRequestCommitChecksUpdatedJob.perform_now(@repo.id, @sha)
  end

  test "it does not trigger a subscription for pull requests if head_sha does not match", skip_enterprise: true do
    commit_2 = @repo.heads.find("master").append_commit({ message: "blah", committer: @user }, @user) do |files|
      files.add("foo", "asdf")
    end
    commit_3 = @repo.heads.find("master").append_commit({ message: "blah", committer: @user }, @user) do |files|
      files.add("foo2", "asdf")
    end
    pull = create_pr(@user, commit_3.oid)

    Platform::Schema.subscriptions.expects(:trigger).never
    NotifyPullRequestCommitChecksUpdatedJob.perform_now(@repo.id, commit_2.oid)
  end

  test "resolves tenant for multi tenant environment" do
    on_multi_tenant_enterprise do
      user = create(:emu)
      GitHub::CurrentTenant.set(user.enterprise_managed_business)
      repo = create(:repository, owner: user, from_example: :simple)

      GitHub::CurrentTenant.remove
      assert_nil GitHub::CurrentTenant.get

      NotifyPullRequestCommitChecksUpdatedJob.perform_now(repo.id, "asdf")
      assert_equal repo.reload.tenant_id, GitHub::CurrentTenant.get.id
    end
  end
end
