# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData::Files::FileTree
    class PayloadTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @user_session = create(:authentication_record, user: @user).user_session
        repo = create(:repository, admin: @user, from_example: :pull_request_history)
        create(:collaborator, collaborator: @user, repository: repo)
        assert repo.member?(@user)

        @pull = create(:pull_request,
          base_ref: repo.default_branch,
          base_repository: repo,
          base_user: @user,
          head_ref_name: "topic",
          head_repository: repo,
          head_user: @user,
          repository: repo,
          user: @user,
        )
        assert_predicate @pull, :valid?

        check_suite = create :check_suite,
                        repository: @pull.repository,
                        head_sha: @pull.head_sha,
                        status: "completed"
        check_run = create :check_run,
                        check_suite: check_suite,
                        name: "run-1",
                        status: "completed",
                        conclusion: "success"
        create(:check_annotation,
                check_run: check_run,
                path: "README.md",
                repository: @pull.repository,
                message: "Integration ran",
                start_line: 14,
                end_line: 14)

        PullRequestReview::Creator.execute(pull_request: @pull,
          user: @user,
          comments: [{ path: "README.md", position: 1, body: "cool" }],
          event: "comment").review

        @base_ref_oid = @pull.base_sha
        @start_commit_oid = @pull.merge_base
        @end_commit_oid = @pull.head_sha
        @viewed_files = PullRequestUserReviews.new(@pull, @user).freeze
      end

      test "serializes data as expected" do
        codeowners = Repository::Codeowners.new(@pull.repository)

        # PullRequest::Comparison cannot be frozen or reloaded, so can't be defined in the fixtures block.
        pull_comparison = PullRequest::Comparison.find(
          pull: @pull,
          start_commit_oid: @start_commit_oid,
          end_commit_oid: @end_commit_oid,
          base_commit_oid: @pull.base_sha
        )

        expected_commits = @pull.changed_commits.map do |commit|
          {
            "actorLogin" => commit.user_display_login,
            "createdAt" => commit.created_at.to_s,
            "messageHeadline" => commit.short_message_text,
            "oid" => commit.oid,
            "shortOid" => commit.abbreviated_oid,
          }
        end

        expected_diffs = pull_comparison.diff.entries.map do |diff_entry|
          {
            "changeType" => Diffs::Entry::ChangeType.deserialize(
              diff_entry.status_label&.upcase
            ),
            "isCodeowner" => codeowners.owners_for_path(diff_entry.path).include?(:current_user),
            "isManifestFile" => false,
            "isVendored" => false,
            "markedAsViewed" => @viewed_files.reviewed?(diff_entry.path),
            "path" => diff_entry.path,
            "pathDigest" => diff_entry.path_digest,
            "highestAnnotationLevel" => "WARNING",
            "totalCommentsCount" => 1,
          }
        end

        expected_payload = {
          "baseRefOid" => @base_ref_oid,
          "commits" => expected_commits,
          "diffs" => expected_diffs,
          "lastReviewOid" => "c78be2730338ba61f8bc0f9a3b8dae0fdfd239cd",
          "ownerLogin" => @pull.repository.owner_display_login,
          "pathName" => @pull.permalink(include_host: false),
          "pullRequestId" => @pull.global_relay_id,
          "pullRequestNumber" => @pull.number,
          "repositoryName" => @pull.repository.name,
        }

        data = PullRequests::PageData::Files::FileTree::Loader.load(
          comparison: pull_comparison,
          current_user: @user,
          pull_request: @pull,
          cap_filter: nil,
          user_session: nil,
          end_commit_oid: @pull.head_sha,
        )

        assert_no_queries do
          actual_payload = PullRequests::PageData::Files::FileTree::Payload.call(data)
          assert_equal expected_payload.as_json, actual_payload.as_json
        end
      end
    end
  end
end
