# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    class CommitsPayloadTest < GitHub::TestCase
      include Commits::ReactPayloadDataDependency

      # Required for Commits::ReactPayloadDataDependency#build_grouped_commits_payload
      def view_context
        TestController.new.view_context
      end

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

        @deferred_commits_data_url = "#{@pull.url(include_host: false)}/deferred_commits_data"
        @expected_time_out_message = "git log #{@pull.head_ref}"

        example_repo_snapshot
      end

      setup do
        example_repo_restore
      end

      test "returns expected payload" do
        Timecop.freeze do # Freeze the time to avoid flakiness of the generated alive channel
          expected_payload = {
            "commitGroups" => build_grouped_commits_payload(@pull.changed_commits, @user, order: :asc, pull_request: @pull),
            "metadata" => {
              "aliveChannel" => GitHub::WebSocket::Channels.signed_pull_request(@pull),
              "deferredCommitsDataUrl" => @deferred_commits_data_url,
            },
            "repository" => {
              "defaultBranch" => @repository.default_branch,
              "name" => @repository.name,
              "ownerLogin" => @repository.owner_display_login,
            },
            "timeOutMessage" => "",
            "truncated" => false,
          }.as_json

          actual_payload = PullRequests::PageData::CommitsPayload.build(
            current_path: "",
            current_user: @user,
            pull_request: @pull,
            tree_name: @pull.head_ref,
          )

          assert_same_hash(expected_payload, actual_payload)
        end
      end

      test "uses fallback value when commits GitRPC request times out" do
        PullRequest.any_instance.stubs(:changed_commits).raises(GitRPC::Timeout.new)
        payload = PullRequests::PageData::CommitsPayload.build(
          current_path: "",
          current_user: @user,
          pull_request: @pull,
          tree_name: @pull.head_ref,
        )
        assert_equal PullRequests::PageData::CommitsPayload::COMMIT_GROUPS_FALLBACK, payload["commitGroups"]
        assert_equal @expected_time_out_message, payload["timeOutMessage"]
      end

      test "uses fallback value when commit limit exceeded GitRPC request times out" do
        PullRequest.any_instance.stubs(:commit_limit_exceeded?).raises(GitRPC::Timeout.new)
        payload = PullRequests::PageData::CommitsPayload.build(
          current_path: "",
          current_user: @user,
          pull_request: @pull,
          tree_name: @pull.head_ref,
        )
        assert_equal PullRequests::PageData::CommitsPayload::COMMIT_GROUPS_FALLBACK, payload["commitGroups"]
        assert_equal @expected_time_out_message, payload["timeOutMessage"]
      end

      test "uses fallback value when commit limit exceeded db query fails" do
        PullRequest.any_instance.stubs(:commit_limit_exceeded?).raises(ActiveRecord::ActiveRecordError.new)
        payload = PullRequests::PageData::CommitsPayload.build(
          current_path: "",
          current_user: @user,
          pull_request: @pull,
          tree_name: @pull.head_ref,
        )
        assert_equal PullRequests::PageData::CommitsPayload::TRUNCATED_FALLBACK, payload["truncated"]
      end
    end
  end
end
