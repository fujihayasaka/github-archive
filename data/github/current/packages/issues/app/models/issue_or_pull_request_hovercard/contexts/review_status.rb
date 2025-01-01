# typed: true
# frozen_string_literal: true

module IssueOrPullRequestHovercard::Contexts
  class ReviewStatus < Hovercard::Contexts::Base
    include PullRequestsHelper

    # Public: Build a ReviewStatus context, if the viewer is involved with the issue or pull
    # request.
    #
    # Returns a Promise that resolves to either a ReviewStatus object or nil.
    def self.async_resolve(issue_or_pull_request:, viewer:)
      if issue_or_pull_request.is_a?(PullRequest)
        Resolver.new(issue_or_pull_request: issue_or_pull_request, viewer: viewer).async_resolve
      else
        Promise.resolve(nil)
      end
    end

    attr_reader :review_decision, :issue_or_pull_request

    def initialize(issue_or_pull_request:, viewer:, viewer_review:, other_reviews:, review_decision:,
                   pending_user_review_request:, pending_user_team_review_request:)
      @issue_or_pull_request = issue_or_pull_request
      @viewer = viewer
      @viewer_review = viewer_review
      @other_reviews = other_reviews
      @review_decision = review_decision
      @pending_user_review_request = pending_user_review_request
      @pending_user_team_review_request = pending_user_team_review_request
    end

    def message
      if pending_user_review_request
        pending_user_review_request_summary
      elsif pending_user_team_review_request
        pending_user_team_review_request_summary
      elsif reviewers_disagree?
        disagreeing_reviewers_review_summary
      elsif viewer_reviewed?
        viewer_review_summary
      else
        viewer_has_not_reviewed_review_summary
      end
    end

    def octicon
      if review_pending?
        "dot-fill"
      elsif changes_requested?
        review_state_octicon_name("changes_requested").to_s
      elsif approved?
        "check"
      elsif review_required? || viewer_reviewed?
        "comment"
      else
        raise "unexpected review status when determining octicon"
      end
    end

    def platform_type_name
      "ReviewStatusHovercardContext"
    end

    private

    attr_reader :viewer_review, :viewer, :other_reviews, :pending_user_review_request, :pending_user_team_review_request

    def viewer_reviewed?
      viewer_review.present?
    end

    def changes_requested?
      review_decision == :changes_requested
    end

    def approved?
      if review_decision
        review_decision == :approved
      else
        # review_decision may be nil when the base branch of the pull request is protected and enforces pull request
        # reviews, but with zero required reviews. In this case, artificially fall back to the way that we consolidate
        # review status with no branch protection at all: if there are no change request reviews and at least one
        # approving review, the pull request is approved.
        !changes_requested? && (viewer_approved? || any_approvals?)
      end
    end

    def review_required?
      review_decision == :review_required
    end

    def review_pending?
      pending_user_review_request || pending_user_team_review_request
    end

    def disagreeing_reviewers_review_summary
      approve_reviews = other_reviews.select(&:approved?)
      change_reviews = other_reviews.select(&:changes_requested?)

      if viewer_approved?
        change_authors = review_authors_from(change_reviews)
        approve_authors = ["you"] + review_authors_from(approve_reviews)

        "Changes requested by #{summarize_users(change_authors)}, " \
          "#{summarize_users(approve_authors)} approved"
      elsif viewer_requested_changes?
        approve_authors = review_authors_from(approve_reviews)
        change_authors = ["You"] + review_authors_from(change_reviews)

        "#{summarize_users(change_authors)} requested changes, " \
          "#{summarize_users(approve_authors)} approved"
      elsif viewer_commented? || viewer_review_dismissed?
        approve_authors = review_authors_from(approve_reviews)
        change_authors = review_authors_from(change_reviews)

        parts = []
        parts << "#{summarize_users(change_authors)} requested changes" if change_authors.any?
        parts << "#{summarize_users(approve_authors)} approved" if approve_authors.any?
        if viewer_commented?
          parts << "you commented"
        elsif viewer_review_dismissed?
          parts << "you left a dismissed review"
        end
        parts.join(", ")
      end
    end

    def viewer_has_not_reviewed_review_summary
      if changes_requested?
        "Changes requested"
      elsif approved?
        "Approved"
      elsif review_required?
        "Review required"
      end
    end

    def review_authors_from(reviews)
      reviews = reviews.reject { |review| review.safe_user.ghost? }
      reviews.map { |review| review.safe_user.login }.uniq
    end

    def summarize_users(logins)
      hovercard_sentence(logins, max: 3)
    end

    def viewer_review_summary
      if viewer_approved?
        reviews = other_reviews.select(&:approved?)
        authors = ["You"] + review_authors_from(reviews)
        "#{summarize_users(authors)} approved this pull request"
      elsif viewer_requested_changes?
        reviews = other_reviews.select(&:changes_requested?)
        authors = ["You"] + review_authors_from(reviews)
        "#{summarize_users(authors)} requested changes"
      elsif viewer_commented?
        "You left a review"
      elsif viewer_review_dismissed?
        "You left a dismissed review"
      else
        raise "Unexpected non-pending review state: #{viewer_review.state}"
      end
    end

    def pending_user_review_request_summary
      "You have a pending review request"
    end

    def pending_user_team_review_request_summary
      "Your team has a pending review request"
    end

    def viewer_approved?
      viewer_review&.approved?
    end

    def viewer_requested_changes?
      viewer_review&.changes_requested?
    end

    def viewer_commented?
      viewer_review&.commented?
    end

    def viewer_review_dismissed?
      viewer_review&.dismissed?
    end

    def reviewers_disagree?
      return false unless viewer_review
      return true if viewer_approved? && any_changes_requested?
      return true if viewer_requested_changes? && any_approvals?

      (viewer_commented? || viewer_review_dismissed?) && (any_changes_requested? || any_approvals?)
    end

    def any_changes_requested?
      other_reviews.any?(&:changes_requested?)
    end

    def any_approvals?
      other_reviews.any?(&:approved?)
    end

    class Resolver
      def initialize(issue_or_pull_request:, viewer:)
        @issue_or_pull_request = issue_or_pull_request
        @viewer = viewer
      end

      def async_resolve
        if should_return_status?
          context = ReviewStatus.new(issue_or_pull_request: issue_or_pull_request, viewer: viewer, viewer_review: latest_review_from_viewer,
                                     other_reviews: other_reviews, review_decision: review_decision,
                                     pending_user_review_request: pending_user_review_request?,
                                     pending_user_team_review_request: pending_user_team_review_request?)
          Promise.resolve(context)
        else
          Promise.resolve(nil)
        end
      end

      private

      attr_reader :issue_or_pull_request, :viewer

      def should_return_status?
        return false if issue_or_pull_request.draft?
        requested_review_involving_user? || !!latest_review_from_viewer || any_final_reviews? || review_required?
      end

      def any_final_reviews?
        other_reviews.any? do |review|
          review.author_can_push_to_repository? && (review.changes_requested? || review.approved?)
        end
      end

      def review_required?
        review_decision == :review_required
      end

      def requested_review_involving_user?
        pending_user_review_request? || pending_user_team_review_request?
      end

      def review_decision
        return @review_decision if defined? @review_decision
        @review_decision = issue_or_pull_request.review_decision(viewer: viewer)
      end

      def latest_review_from_viewer
        return @latest_review_from_viewer if defined? @latest_review_from_viewer

        @latest_review_from_viewer = issue_or_pull_request.latest_non_pending_review_for(viewer)
      end

      def other_reviews
        return @other_reviews if @other_reviews

        reviews = issue_or_pull_request.latest_reviews_for(viewer)
        reviews = reviews.where("pull_request_reviews.user_id <> ?", viewer.id) if viewer

        if latest_review_from_viewer
          reviews = reviews.where("pull_request_reviews.id <> ?", latest_review_from_viewer.id)
        end

        @other_reviews = reviews.group_by(&:user_id).map do |_user_id, reviews|
          reviews.max_by(&:submitted_at)
        end
      end

      def pending_user_review_request?
        return @pending_user_review_request if @pending_user_review_request

        # if the reviewer has already left a review OR there are no reviews requested
        # this should be false
        @pending_user_review_request = if latest_review_from_viewer || issue_or_pull_request.review_requests.empty?
          false
        else
          issue_or_pull_request.review_requests.exists?(reviewer_type: "User", reviewer_id: viewer.id)
        end
      end

      def pending_user_team_review_request?
        return @pending_user_team_review_request if @pending_user_team_review_request

        pending_team_review_requests = issue_or_pull_request.can_fulfill_a_pending_team_review_request?(viewer)

        @pending_user_team_review_request = if latest_review_from_viewer || !pending_team_review_requests
          false
        else
          true
        end
      end
    end
  end
end
