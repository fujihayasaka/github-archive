# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module PullRequests
  module PageData::Files::CopilotDiffChat
    class LoaderTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @user.split_diff_preferred = "split"
        @user_session = create(:authentication_record, user: @user).user_session

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

      test "returns expected payload" do
        base_oid = @pull.historical_comparison.async_base_oid.sync
        head_oid = @pull.historical_comparison.async_head_oid.sync

        expected_payload = {
          "base_owner_login" => @repository.owner.display_login,
          "base_repository" => @repository,
          "entries" => [@pull.pull_comparison(
            start_oid: base_oid,
            end_oid: head_oid,
            base_oid: base_oid
          ).diffs.first],
          "head_owner_login" => @repository.owner.display_login,
          "head_repository" => @repository,
        }

        actual_payload = PullRequests::PageData::CopilotDiffChat::Loader.load(
          base_oid: @pull.historical_comparison.async_base_oid.sync,
          head_oid: @pull.historical_comparison.async_head_oid.sync,
          pull_request: @pull,
        )

        # Diff entries serialize only the first line of the text, so we can't compare them directly
        assert_equal expected_payload["base_owner_login"], actual_payload.base_owner_login
        assert_equal expected_payload["base_repository"], actual_payload.base_repository
        assert_equal expected_payload["entries"].first.to_json, actual_payload.entries.first.to_json
        assert_equal expected_payload["head_owner_login"], actual_payload.head_owner_login
        assert_equal expected_payload["head_repository"], actual_payload.head_repository
      end
    end
  end
end
