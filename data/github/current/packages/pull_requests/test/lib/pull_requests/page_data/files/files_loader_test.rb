# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module PullRequests
  module PageData::Files
    class LoaderTest < GitHub::TestCase
      include GitHub::QueryAssertionTestHelpers

      fixtures do
        @user = create(:user)
        @repo = create(:repository, admin: @user, from_example: :pull_request_history)
        create(:collaborator, collaborator: @user, repository: @repo)
        assert @repo.member?(@user)

        @pull = create(:pull_request,
          base_ref: @repo.default_branch,
          base_repository: @repo,
          base_user: @user,
          head_ref_name: "topic",
          head_repository: @repo,
          head_user: @user,
          repository: @repo,
          user: @user,
        )

        assert_predicate @pull, :valid?

        @base_ref_oid = @pull.base_sha
        @end_commit_oid = @pull.head_sha
        @start_commit_oid = @pull.merge_base
      end

      test "returns expected data for logged in user" do
        enable_feature_flag(:copilot_workspace)

        Timecop.freeze do # Freeze the time to avoid flakiness of the generated alive channel
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @end_commit_oid,
            pull: @pull,
            start_commit_oid: @start_commit_oid,
            viewer: @user,
          )

          actual_data = assert_query_counts(35) do
            PullRequests::PageData::Files::Loader.load(
              comparison: pull_comparison,
              current_user: @user,
              pull_request: @pull,
              cap_filter: nil,
              user_session: nil,
              timeout: 2,
              ignore_whitespace: false,
            )
          end.serialize

          file_tree_data = {
            "base_ref_oid" => @base_ref_oid,
            "codeowners" => Repository::Codeowners.new(@pull.repository),
            "commits" => @pull.changed_commits,
            "diffs" => pull_comparison.diff.summary.deltas.map do |diff|
              {
                "diff_delta" => diff,
                "is_codeowner" => false,
                "tree_entry" => TreeEntry.new(@pull.repository, {
                  "oid" => diff.new_file.oid,
                  "path" => diff.new_file.path,
                  "mode" => diff.new_file.mode,
                  "type" => "blob",
                }),
              }
            end,
            "pull_request" => @pull,
            "repository" => @pull.repository,
            "viewed_files" => PullRequestUserReviews.new(@pull, @user),
          }

          assert_equal file_tree_data["base_ref_oid"], actual_data["file_tree"]["base_ref_oid"]
          assert_equal file_tree_data["commits"], actual_data["file_tree"]["commits"]

          # GitHub::Diff::Entry objects cannot be compared directly, so we assert on path instead
          assert_equal file_tree_data["diffs"].map { |diff| diff["diff_delta"].path }, actual_data["file_tree"]["diffs"].map { |diff| diff["diff_delta"].path }
          assert_equal file_tree_data["diffs"].map { |diff| diff["tree_entry"] }, actual_data["file_tree"]["diffs"].map { |diff| diff["tree_entry"] }
          assert_equal file_tree_data["diffs"].map { |diff| diff["is_codeowner"] }, actual_data["file_tree"]["diffs"].map { |diff| diff["is_codeowner"] }

          assert_same_elements file_tree_data["viewed_files"].reviewed_paths, actual_data["file_tree"]["viewed_files"].reviewed_paths


          toolbar_data = {
            "annotations" => [],
            "copilot_access_allowed" => true,
            "current_user" => @user,
            "is_file_tree_expanded" => true,
            "pull_request" => {
              "alive_channel" => GitHub::WebSocket::Channels.signed_pull_request(@pull),
              "author" => @user,
              "historical_comparison" => {
                "base_oid" => @pull.historical_comparison.async_base_oid.sync,
                "head_oid" => @pull.historical_comparison.async_head_oid.sync
              },
              "id" => @pull.global_relay_id,
              "path_name" => @pull.permalink(include_host: false),
              "repository" => @repo,
              "state" => :open,
              "viewer_can_leave_non_comment_reviews" => false,
              "viewer_has_violated_push_policy" => false,
              "viewer_permission" => "write"
            },
            "should_show_viewed_files_count" => true,
            "thread_previews" => [],
            "total_files_count" => 1,
            "viewed_files_count" => 0,
            "viewer_pending_review" => { "review_comments" => [] },
            "view_settings" => {
              "hide_whitespace" => false,
              "line_spacing" => "relaxed",
              "split_preference" => "unified",
              "comments_preference" => "visible",
            }
          }

          assert_equal toolbar_data, actual_data["toolbar"]

          base_url = @pull.url(include_host: false)

          header_data = {
            "aliveChannel" => GitHub::WebSocket::Channels.signed_pull_request(@pull),
            "bannersData" => {
              "banners" => {
                "dependabotAutomatedSecurityUpdates" => { "render" => false },
                "pausedDependabotUpdate" => { "render" => false },
                "hiddenCharacterWarning" => { "render" => false }
              }
            },
            "pullRequest" => {
              "author" => {
                "login" => @pull.user.display_login,
              },
              "baseBranch" => @pull.display_base_ref_name,
              "commitsCount" => 1, # Known value from fixtures above
              "headBranch" => @pull.display_head_ref_name,
              "headRepositoryName" => @repo.name,
              "headRepositoryOwnerLogin" => @repo.owner_display_login,
              "isInAdvisoryRepo" => @pull.in_advisory_workspace?,
              "mergedBy" => nil, # Known value from fixtures above
              "mergedTime" => nil, # Known value from fixtures above
              "number" => @pull.number,
              "relayId" => @pull.global_relay_id,
              "state" => @pull.state.to_s.upcase,
              "title" => @pull.title,
              "titleHtml" => @pull.title_html,
            },
            "repository" => {
              "codespacesEnabled" => GitHub.codespaces_enabled?,
              "copilotEnabled" => @repo.feature_enabled?(:copilot_workspace),
              "editorEnabled" => @repo.owner.feature_preview_enabled?(:copilot_hadron_editor), # Assumes that the owner of the repository is the user from the fixtures
              "defaultBranch" => @repo.default_branch,
              "id" => @repo.id,
              "isEnterprise" => GitHub.enterprise?,
              "name" => @repo.name,
              "ownerLogin" => @repo.owner_display_login,
            },
            "urls" => {
              "checks" => "#{base_url}/checks",
              "commits" => "#{base_url}/commits",
              "conversation" => base_url,
              "files" => "#{base_url}/files",
              "walkthrough" => "#{base_url}/walkthrough",
            },
            "user" => {
              "canChangeBase" => true,
              "canEditTitle" => true,
            },
          }

          assert_equal header_data, actual_data["header"]
        end
      end

      test "returns expected data for a logged in user with a last review" do
        review = create(:pull_request_review, pull_request: @pull,
          user: @user,
          head_sha: @pull.head_sha,
          state: PullRequestReview.state_value(:commented)
        )

        pull_comparison = PullRequest::Comparison.find(
          base_commit_oid: @pull.base_sha,
          end_commit_oid: @end_commit_oid,
          pull: @pull,
          start_commit_oid: @start_commit_oid,
          viewer: @user,
        )

        actual_data = assert_query_counts(31) do
          PullRequests::PageData::Files::Loader.load(
            comparison: pull_comparison,
            current_user: @user,
            pull_request: @pull,
            cap_filter: nil,
            user_session: nil,
            timeout: 2,
            ignore_whitespace: false,
          )
        end.serialize

        expected_data = {
          "last_review_oid" => @pull.head_sha,
        }

        assert_equal expected_data["last_review_oid"], actual_data["file_tree"]["last_review_oid"]
      end


      test "returns expected data for logged out user" do
        disable_feature_flag(:copilot_workspace)

        Timecop.freeze do # Freeze the time to avoid flakiness of the generated alive channel
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @end_commit_oid,
            pull: @pull,
            start_commit_oid: @start_commit_oid,
            viewer: @user,
          )

          actual_data = assert_query_counts(21) do
            PullRequests::PageData::Files::Loader.load(
              comparison: pull_comparison,
              pull_request: @pull,
              cap_filter: nil,
              user_session: nil,
              timeout: 2,
              ignore_whitespace: false,
            )
          end.serialize

          expected_file_tree_data = {
            "base_ref_oid" => @base_ref_oid,
            "codeowners" => Repository::Codeowners.new(@pull.repository),
            "commits" => @pull.changed_commits,
            "diffs" => pull_comparison.diff.summary.deltas.map do |diff|
              {
                "diff_delta" => diff,
                "is_codeowner" => false,
                "tree_entry" => TreeEntry.new(@pull.repository, {
                  "oid" => diff.new_file.oid,
                  "path" => diff.new_file.path,
                  "mode" => diff.new_file.mode,
                  "type" => "blob",
                }),
              }
            end,
            "viewed_files" => PullRequestUserReviews.new(@pull, @user),
          }

          assert_equal expected_file_tree_data["base_ref_oid"], actual_data["file_tree"]["base_ref_oid"]
          assert_equal expected_file_tree_data["commits"], actual_data["file_tree"]["commits"]

          # GitHub::Diff::Entry objects cannot be compared directly, so we assert on path instead
          assert_equal expected_file_tree_data["diffs"].map { |diff| diff["diff_delta"].path }, actual_data["file_tree"]["diffs"].map { |diff| diff["diff_delta"].path }
          assert_equal expected_file_tree_data["diffs"].map { |diff| diff["tree_entry"] }, actual_data["file_tree"]["diffs"].map { |diff| diff["tree_entry"] }
          assert_equal expected_file_tree_data["diffs"].map { |diff| diff["is_codeowner"] }, actual_data["file_tree"]["diffs"].map { |diff| diff["is_codeowner"] }

          assert_same_elements expected_file_tree_data["viewed_files"].reviewed_paths, actual_data["file_tree"]["viewed_files"].reviewed_paths

          toolbar_data = {
            "annotations" => [],
            "copilot_access_allowed" => false,
            "is_file_tree_expanded" => true,
            "pull_request" => {
              "alive_channel" => GitHub::WebSocket::Channels.signed_pull_request(@pull),
              "author" => @user,
              "historical_comparison" => {
                "base_oid" => @pull.historical_comparison.async_base_oid.sync,
                "head_oid" => @pull.historical_comparison.async_head_oid.sync
              },
              "id" => @pull.global_relay_id,
              "path_name" => @pull.permalink(include_host: false),
              "repository" => @repo,
              "state" => :open,
              "viewer_can_leave_non_comment_reviews" => false,
              "viewer_has_violated_push_policy" => false,
              "viewer_permission" => "read"
            },
            "should_show_viewed_files_count" => false,
            "thread_previews" => [],
            "total_files_count" => 1,
            "viewed_files_count" => 0,
            "viewer_pending_review" => { "review_comments" => [] },
            "view_settings" => {
              "hide_whitespace" => false,
              "line_spacing" => "relaxed",
              "split_preference" => "unified",
              "comments_preference" => "visible",
            }
          }

          assert_equal toolbar_data, actual_data["toolbar"]

          base_url = @pull.url(include_host: false)

          header_data = {
            "aliveChannel" => GitHub::WebSocket::Channels.signed_pull_request(@pull),
            "bannersData" => {
              "banners" => {
                "dependabotAutomatedSecurityUpdates" => { "render" => false },
                "pausedDependabotUpdate" => { "render" => false },
                "hiddenCharacterWarning" => { "render" => false }
              }
            },
            "pullRequest" => {
              "author" => {
                "login" => @pull.user.display_login,
              },
              "baseBranch" => @pull.display_base_ref_name,
              "commitsCount" => 1, # Known value from fixtures above
              "headBranch" => @pull.display_head_ref_name,
              "headRepositoryName" => @repo.name,
              "headRepositoryOwnerLogin" => @repo.owner_display_login,
              "isInAdvisoryRepo" => @pull.in_advisory_workspace?,
              "mergedBy" => nil, # Known value from fixtures above
              "mergedTime" => nil, # Known value from fixtures above
              "number" => @pull.number,
              "relayId" => @pull.global_relay_id,
              "state" => @pull.state.to_s.upcase,
              "title" => @pull.title,
              "titleHtml" => @pull.title_html,
            },
            "repository" => {
              "codespacesEnabled" => false,
              "copilotEnabled" => @repo.feature_enabled?(:copilot_workspace),
              "editorEnabled" => @repo.owner.feature_preview_enabled?(:copilot_hadron_editor), # Assumes that the owner of the repository is the user from the fixtures
              "defaultBranch" => @repo.default_branch,
              "id" => @repo.id,
              "isEnterprise" => GitHub.enterprise?,
              "name" => @repo.name,
              "ownerLogin" => @repo.owner_display_login,
            },
            "urls" => {
              "checks" => "#{base_url}/checks",
              "commits" => "#{base_url}/commits",
              "conversation" => base_url,
              "files" => "#{base_url}/files",
              "walkthrough" => "#{base_url}/walkthrough",
            },
            "user" => {
              "canChangeBase" => false,
              "canEditTitle" => false,
            },
          }

          assert_equal header_data, actual_data["header"]
        end
      end
    end
  end
end
