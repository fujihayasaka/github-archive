# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  class CleanupHeadRefJobTest < GitHub::TestCase
    include GitHub::LoggerHelper

    fixtures do
      @owner = create(:user, login: "owner")
      @source = create(:repository, owner: @owner, from_example: :pull_request_source)
      @pull_request = create(:pull_request, :with_mergeable_head, repository: @source)
      @pull_request.repository.update_merge_settings(@owner, delete_branch_allowed: true)

      enable_feature_flag(:async_delete_branch_on_merge)

      example_repo_snapshot
    end

    setup do
      example_repo_restore
    end

    test "deletes the head ref of a pull request" do
      assert @pull_request.repository.heads.exist?(@pull_request.head_ref)

      @pull_request.merge

      PullRequests::CleanupHeadRefJob.perform_now(pull_request: @pull_request, actor: @owner)

      refute @pull_request.reload.repository.heads.exist?(@pull_request.head_ref)
    end
  end
end
