# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents::ReviewRequest
  # The description of an event of type `review_requested` or
  # `review_request_removed`.
  #
  #
  # it is possible in some cases that we have `review_request` value set to `nil`, for example:
  # - Request review for a PR -> issue event created with #event = "review_requested"
  # - Remove the requested review -> review_request record is deleted
  # This leads to have issue_event.review_request equals to nil
  # Accordingly, a presence check on `review_request` must be considered
  # when accessing methods of `review_request` (i.e: `review_request.<some-method>`)
  class SingleDescriptionComponent < ApplicationComponent
    attr_reader :issue_event, :pull_request, :actor

    def initialize(issue_event:, actor:, pull_request:)
      @issue_event = issue_event
      @actor = actor
      @pull_request = pull_request
    end

    memoize def review_request
      issue_event.review_request
    end

    # Ported from ReviewRequestedEvent#requested_review_team_name
    def requested_review_team_name
      return unless requested_reviewer.is_a?(Team)
      requested_reviewer.async_organization.then { |org| "#{org.name}/#{requested_reviewer.slug}" }.sync
    end

    memoize def requested_reviewer
      issue_event.visible_subject_for(current_user)
    end

    def missing_reviewer_name
      return nil if requested_reviewer.present?

      issue_event.subject_type == "Team" ? "a team" : "a user"
    end

    def as_code_owner?
      return false if review_request.nil?

      review_requested? && review_request.async_as_codeowner?&.sync
    end

    def as_copilot?
      return !!review_request&.async_as_copilot?&.sync if review_requested?

      # being a little sneaky here to reduce queries - looking for the CCR bot, but with the ID of the event subject
      # if this doesn't turn up then either the bot isn't installed or the subject isn't Copilot
      Integration.where(
        bot_id: issue_event.subject&.id,
        owner_id: GitHub.trusted_apps_owner_id,
        slug: Apps::Privileged::CopilotPullRequestReviewer::SLUG
      ).exists?
    end

    def review_requested?
      issue_event.event == "review_requested"
    end

    def request_removed?
      !review_requested?
    end

    def self_request?
      actor == requested_reviewer
    end

    def self_action_description
      return "could not review due to quota limits" if as_copilot? && request_removed?
      review_requested? ? "self-requested a review" : "removed their request for review"
    end

    def copilot_action_description
      "review requested due to automatic review settings"
    end

    def action_description
      review_requested? ? "requested a review" : "removed the request for review"
    end

    def assigned_from_team_name
      review_request&.prelude_visible_assigned_from_team_name(current_user)
    end

    def codeowner_link
      return if request_removed? || review_request.nil?

      href = review_request.async_codeowners_path_uri&.sync
      if href.present?
        render(Primer::Beta::Link.new(href: href, scheme: :secondary)) { "code owner" }
      end
    end
  end
end
