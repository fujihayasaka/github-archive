# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    class HeaderPayloadTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @repository = create(:repository, admin: @user, from_example: :review_comment_fork)
        create(:collaborator, collaborator: @user, repository: @repository)
        assert @repository.member?(@user)

        @pull = create(:pull_request,
          :with_mergeable_head,
          repository: @repository,
          base_repository: @repository,
          base_user: @user,
          base_ref: @repository.default_branch,
          head_repository: @repository,
          head_user: @user,
          head_ref_name: "topic2",
          user: @user,
        )

        example_repo_snapshot
      end

      setup do
        example_repo_restore
      end

      test "returns expected payload" do
        base_url = @pull.url(include_host: false)
        expected_payload = {
          "bannersData" => {
            "banners" => {
              "dependabotAutomatedSecurityUpdates" => { "render" => false },
              "pausedDependabotUpdate" => { "render" => false },
              "hiddenCharacterWarning" => { "render" => false }
            }
          },
          "pullRequest" => {
            "author" => @pull.user.display_login,
            "baseBranch" => @pull.display_base_ref_name,
            "commitsCount" => 1, # Known value from fixtures above
            "headBranch" => @pull.display_head_ref_name,
            "headRepositoryName" => @repository.name,
            "headRepositoryOwnerLogin" => @repository.owner_display_login,
            "isInAdvisoryRepo" => @pull.in_advisory_workspace?,
            "linesAdded" => 1,
            "linesChanged" => 1,
            "linesDeleted" => 0,
            "mergedBy" => nil, # Known value from fixtures above
            "mergedTime" => nil, # Known value from fixtures above
            "number" => @pull.number,
            "state" => @pull.state.to_s,
            "title" => @pull.title,
            "titleHtml" => @pull.title_html,
          },
          "repository" => {
            "codespacesEnabled" => GitHub.codespaces_enabled?,
            "copilotEnabled" => @repository.feature_enabled?(:copilot_workspace),
            "editorEnabled" => @repository.owner.feature_preview_enabled?(:copilot_hadron_editor), # Assumes that the owner of the repository is the user from the fixtures
            "defaultBranch" => @repository.default_branch,
            "id" => @repository.id,
            "isEnterprise" => GitHub.enterprise?,
            "name" => @repository.name,
            "ownerLogin" => @repository.owner_display_login,
          },
          "urls" => {
            "checks" => "#{base_url}/checks",
            "commits" => "#{base_url}/commits",
            "conversation" => base_url,
            "files" => "#{base_url}/files",
          },
          "user" => {
            "canChangeBase" => true,
            "canEditTitle" => true,
          },
        }
        payload = PullRequests::PageData::HeaderPayload.build(pull_request: @pull, current_user: @user)
        assert_equal expected_payload, payload
      end

      test "uses fallback value when commits count GitRPC request fails" do
        GitHub::Comparison.any_instance.stubs(:total_commits).raises(GitRPC::Error.new)
        payload = PullRequests::PageData::HeaderPayload.build(pull_request: @pull, current_user: @user)
        assert_equal PullRequests::PageData::HeaderPayload::COMMITS_COUNT_FALLBACK, payload["pullRequest"]["commitsCount"]
      end

      test "uses fallback value when 'current user can change base' permissions query fails" do
        PullRequest.any_instance.stubs(:can_change_base_branch?).raises(ActiveRecord::ActiveRecordError.new)
        payload = PullRequests::PageData::HeaderPayload.build(pull_request: @pull, current_user: @user)
        assert_equal PullRequests::PageData::HeaderPayload::CURRENT_USER_CAN_CHANGE_BASE_FALLBACK, payload["user"]["canChangeBase"]
      end

      test "uses fallback value when 'current user can edit title' permissions query fails" do
        Repository.any_instance.stubs(:async_authorized_to_write?).raises(ActiveRecord::ActiveRecordError.new)
        payload = PullRequests::PageData::HeaderPayload.build(pull_request: @pull, current_user: @user)
        assert_equal PullRequests::PageData::HeaderPayload::CURRENT_USER_CAN_EDIT_TITLE_FALLBACK, payload["user"]["canEditTitle"]
      end
    end
  end
end
