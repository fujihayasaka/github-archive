# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd::Mobile
  class NotifydPullRequestReviewTest < GitHub::TestCase
    fixtures do
      @owner = create(:user, login: "owner")
      @author = create(:user, login: "author")
      @reviewer = create(:user, login: "reviewer")
      @repo = create(:repository, owner: @owner, name: "repo")
      @pull_request = create(:pull_request, :disable_disk_access, user: @author, repository: @repo)
      @review = create(:pull_request_review, pull_request: @pull_request, user: @reviewer)
    end

    test "layout #body" do
      layout = renderer(@review).render

      assert_equal @review.body, layout.body
    end

    test "layout #url" do
      layout = renderer(@review).render

      assert_equal @review.permalink, layout.url
    end

    test "layout #subtitle" do
      layout = renderer(@review).render

      assert_equal "owner/repo ##{@pull_request.number}", layout.subtitle
    end

    context "when the author exists" do
      test "author provile info" do
        layout = renderer(@review).render

        refute_predicate layout.avatar_url, :empty?
        refute_predicate layout.avatar_url, :empty?
        refute_predicate layout.avatar_url, :empty?
      end
    end

    context "when the author does not exist" do
      test "author provile info" do
        reviewer = create(:user)
        review = create(:pull_request_review, pull_request: @pull_request, user: reviewer)
        reviewer.destroy
        review.reload

        layout = renderer(review).render

        assert_predicate layout.avatar_url, :empty?
        assert_predicate layout.avatar_url, :empty?
        assert_predicate layout.avatar_url, :empty?
      end
    end

    context "layout #title" do
      test "for approved review" do
        @review.approve!
        layout = renderer(@review).render

        assert_equal "@reviewer approved your pull request", layout.title
      end

      test "for commented review" do
        @review.comment!
        layout = renderer(@review).render

        assert_equal "@reviewer wrote a review comment on your pull request", layout.title
      end

      test "for changes requested review" do
        @review.request_changes!
        layout = renderer(@review).render

        assert_equal "@reviewer requested changes on your pull request", layout.title
      end
    end

    test "layout #thread_id" do
      pr = @review.pull_request
      layout = renderer(@review).render

      assert_equal pr.permalink(include_host: false), layout.thread_id
    end

    test "layout #thread_type" do
      pr = @review.pull_request
      layout = renderer(@review).render

      assert_equal "pull_request", layout.thread_type
    end

    private

    def renderer(review)
      PullRequestReviewRenderer.new(review: review, pull_request: T.must(review.pull_request))
    end
  end
end
