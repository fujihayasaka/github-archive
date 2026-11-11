# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  # Event describing one or more pull request reviews that were dismissed.
  class ReviewDismissedComponent < ApplicationComponent
    COMPACT_DISMISSAL_MESSAGE_MAX_LENGTH = 140

    def initialize(issue_events:, pull_request:)
      @issue_events = issue_events
      @pull_request = pull_request
    end

    memoize def actor
      first_event.event_actor(viewer: current_user)
    end

    # A component describing the action that was taken including the
    # authors of the dismissed review or reviews.
    def description_component
      if single_event?
        PullRequests::TimelineEvents::ReviewDismissed::SingleDescriptionComponent.new(
          issue_event: first_event, actor: actor, pull_request: @pull_request
        )
      else
        PullRequests::TimelineEvents::ReviewDismissed::MultipleDescriptionComponent.new(
          issue_events: @issue_events, actor: actor, pull_request: @pull_request
        )
      end
    end

    # Note: this and the other commit_ methods do things differently
    # than the graphql loader to avoid a gitrpc call and just use the commit
    # oid from the db as-is.
    memoize def commit_oid
      first_event.after_commit_oid
    end

    def commit_path
      if commit_oid
        repo = first_event.repository
        "/#{repo.owner_display_login}/#{repo}/commit/#{commit_oid}"
      end
    end

    def abbreviated_commit_oid
      if commit_oid
        commit_oid[0, Commit::ABBREVIATED_OID_LENGTH]
      end
    end

    memoize def dismissal_message_html
      first_event.dismissal_message
    end

    def compact_description_html
      safe_join(["dismissed their ", compact_review_link])
    end

    memoize def compact_dismissal_message_text
      helpers.strip_tags_and_collapse_whitespace(dismissal_message_html)
    end

    # The reason rendered inline as a continuation of the event sentence
    # (e.g. "...dismissed their stale review, a newer Copilot review was
    # requested."), so the leading character is lower-cased.
    def compact_dismissal_message_display
      compact_dismissal_message_text.sub(/\A./) { |char| char.downcase }
    end

    memoize def compact_dismissal_message?
      dismissal_message_html.present? &&
        single_event? &&
        compact_dismissal_message_text.length <= COMPACT_DISMISSAL_MESSAGE_MAX_LENGTH &&
        copilot_pull_request_reviewer?(actor) &&
        copilot_pull_request_reviewer?(dismissed_review&.user) &&
        compact_review_dismissal_timeline_enabled?
    end

    private

    def single_event?
      @issue_events.size == 1
    end

    memoize def first_event
      @issue_events.first
    end

    memoize def dismissed_review
      review_id = first_event.pull_request_review_id
      return unless review_id

      @pull_request.reviews_for(current_user).find { |review| review.id == review_id }
    end

    def compact_review_link
      review = dismissed_review
      return "stale review" unless review

      render(Primer::Beta::Link.new(href: "##{review.anchor}", scheme: :secondary)) { "stale review" }
    end

    def copilot_pull_request_reviewer?(user)
      user.is_a?(Bot) && user.slug == Apps::Privileged::CopilotPullRequestReviewer::SLUG
    end

    def compact_review_dismissal_timeline_enabled?
      repo = @pull_request.repository
      return false unless repo

      FeatureFlag.vexi.enabled?(:ccr_compact_review_dismissal_timeline, repo, repo.owner, default: false)
    end
  end
end
