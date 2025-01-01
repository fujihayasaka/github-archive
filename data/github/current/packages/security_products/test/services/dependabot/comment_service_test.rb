# typed: true
# frozen_string_literal: true

require "test_helper"

module Dependabot
  class CommentServiceTest < GitHub::TestCase
    fixtures do
      # Dependabot is not a user, but for this test it doesn't matter
      @dependabot_user = create(:user, login: "dependabot")
      @repo = create(:repository, from_example: :simple, owner: @dependabot_user)

      @pull_request = create(:pull_request, repository: @repo, base_ref: "master", head_ref: "cr-line-endings")
    end

    setup do
      @service = CommentService.new(pull_request: @pull_request, dependabot_user: @dependabot_user)
    end

    context "#post_comment_on_missing_data" do
      test "does not post a comment when everything is fine" do
        assert_no_difference -> { @pull_request.issue.comments.count } do
          @service.post_comment_on_missing_data
        end
      end

      test "posts a comment when a label is missing" do
        @service.missing_labels = ["foo"]
        assert_difference -> { @pull_request.issue.comments.count }, 1 do
          @service.post_comment_on_missing_data
        end
        comment = @pull_request.issue.comments.last
        assert_includes comment.body, "The following labels could not be found: `foo`."
      end

      test "posts a comment when a milestone is missing" do
        @service.missing_milestone = true
        assert_difference -> { @pull_request.issue.comments.count }, 1 do
          @service.post_comment_on_missing_data
        end
        comment = @pull_request.issue.comments.last
        assert_includes comment.body, "The specified milestone could not be found on this repository."
      end

      test "posts a comment when a user is disallowed" do
        @service.disallowed_users = ["foo"]
        assert_difference -> { @pull_request.issue.comments.count }, 1 do
          @service.post_comment_on_missing_data
        end
        comment = @pull_request.issue.comments.last
        assert_includes comment.body, "The following users could not be added as reviewers: `foo`."
      end

      test "posts a comment when a team is disallowed" do
        team = create(:team)
        @service.disallowed_teams = [team.slug]
        assert_difference -> { @pull_request.issue.comments.count }, 1 do
          @service.post_comment_on_missing_data
        end
        comment = @pull_request.issue.comments.last
        assert_includes comment.body, "The following teams could not be added as reviewers: `#{team.slug}`."
      end

      test "posts a comment when an assignee is disallowed" do
        @service.disallowed_assignees = ["foo"]
        assert_difference -> { @pull_request.issue.comments.count }, 1 do
          @service.post_comment_on_missing_data
        end
        comment = @pull_request.issue.comments.last
        assert_includes comment.body, "The following users could not be added as assignees: `foo`."
      end
    end
  end
end
