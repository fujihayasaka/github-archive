# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class CodeScanningReviewCommentTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    make_trusted_oauth_apps_owner
    code_scanning_integration = create(:code_scanning_integration)
    @code_scanning_bot = code_scanning_integration.bot
    @pull_request = make_pr_and_repos
  end

  context "format_body" do
    test "correctly produces a body message" do
      alert = Turboscan::Proto::DiffedAlert.new(
        number: 1,
        rule_short_description: "Test Title!",
        message_text: "Test Message!",
      )
      assert_equal "## Test Title!\n\nTest Message!\n\n[Show more details](https://github.com/#{@pull_request.repository.nwo}/security/code-scanning/#{alert.number})", CodeScanningReviewComment.format_body(alert: alert, repository: @pull_request.repository)
    end

    test "handles missing information" do
      alert = Turboscan::Proto::DiffedAlert.new(
        number: 1,
      )
      assert_equal "[Show more details](https://github.com/#{@pull_request.repository.nwo}/security/code-scanning/#{alert.number})", CodeScanningReviewComment.format_body(alert: alert, repository: @pull_request.repository)

      alert = Turboscan::Proto::DiffedAlert.new(
        rule_short_description: "Test Title!",
        number: 1,
      )
      assert_equal "## Test Title!\n\n[Show more details](https://github.com/#{@pull_request.repository.nwo}/security/code-scanning/#{alert.number})", CodeScanningReviewComment.format_body(alert: alert, repository: @pull_request.repository)

      alert = Turboscan::Proto::DiffedAlert.new(
        rule_short_description: "Test Title!",

      )
      assert_equal "## Test Title!", CodeScanningReviewComment.format_body(alert: alert, repository: @pull_request.repository)
    end
  end

  context "#fix!" do
    test "correctly marks the alert as fixed if value was false" do
      code_scanning_review_comment = create(:code_scanning_review_comment, pull_request: @pull_request, user: @code_scanning_bot)
      code_scanning_review_comment.fix!
      code_scanning_review_comment.reload
      assert code_scanning_review_comment.fixed?
    end
  end

  context "creation" do
    test "correctly sets fixed to false if nil" do
      code_scanning_review_comment = create(:code_scanning_review_comment, fixed: nil, pull_request: @pull_request, user: @code_scanning_bot)
      refute code_scanning_review_comment.nil?
    end
  end

  context "dependent destroy" do
    test "CodeScanningReviewComment is deleted if the associated PR is" do
      code_scanning_review_comment = create(:code_scanning_review_comment, fixed: nil, pull_request: @pull_request, user: @code_scanning_bot)
      comment_id = code_scanning_review_comment.id

      perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
        @pull_request.destroy
        assert_equal false, CodeScanningReviewComment.exists?(comment_id), "Comment was not deleted"
      end
    end
  end
end
