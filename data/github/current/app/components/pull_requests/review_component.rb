# typed: true
# frozen_string_literal: true

module PullRequests
  class ReviewComponent < ApplicationComponent
    include HovercardHelper
    include CommentsHelper
    include AvatarHelper

    MAX_TEAMS_TO_DISPLAY = 5
    THREADS_TO_DISPLAY = 10

    attr_reader :pull_request, :pull_request_review, :dom_id, :render_if_minimized

    def initialize(pull_request:, pull_request_review:, render_if_minimized: false)
      @pull_request = pull_request
      @pull_request_review = pull_request_review
      @dom_id = comment_dom_id(pull_request_review)
      @render_if_minimized = render_if_minimized
    end

    memoize def author
      pull_request_review.async_user.then do |user|
        next User.ghost if user.nil? || user.hide_from_user?(current_user)

        user
      end.sync
    end

    def state_classes
      class_names("is-pending" => pull_request_review.pending?)
    end

    def badge_icon
      if pull_request_review.approved?
        "check"
      elsif pull_request_review.changes_requested? && pull_request_review.writer?
        "file-diff"
      else
        "eye"
      end
    end

    def badge_tooltip
      return if pull_request_review.writer?
      "Only reviews by reviewers with write access count toward mergeability"
    end

    def badge_color
      return unless pull_request_review.writer?

      if pull_request_review.approved? || pull_request_review.changes_requested?
        :on_emphasis
      end
    end

    def badge_background_color
      return unless pull_request_review.writer?

      if pull_request_review.approved?
        :success_emphasis
      elsif pull_request_review.changes_requested?
        :danger_emphasis
      end
    end

    def live_update_channel
      GitHub::WebSocket::Channels.pull_request_review(pull_request_review)
    end

    def live_update_url
      pull_request_review_partial_path(id: pull_request.number, review_id: pull_request_review.id)
    end

    def state_action_string
      if pull_request_review.approved?
        "approved these changes"
      elsif pull_request_review.changes_requested? && pull_request_review.writer?
        "requested changes"
      elsif pull_request_review.changes_requested?
        "suggested changes"
      elsif pull_request_review.pending?
        "started a review"
      elsif pull_request_review.dismissed?
        state = pull_request_review.dismissed_review_state
        if state == PullRequestReview.state_value(:approved)
          "previously approved these changes"
        elsif state == PullRequestReview.state_value(:changes_requested)
          "previously requested changes"
        else
          "reviewed"
        end
      elsif pull_request_review.code_scanning?
        "found potential problems"
      elsif pull_request_review.user_id == pull_request.user_id
        "commented"
      else
        "reviewed"
      end
    end

    memoize def anchor
      pull_request_review.async_path_uri.sync.fragment
    end

    def diff_path
      if pull_request_review.applies_to_current_diff?
        pull_request_review.async_diff_uri.sync
      else
        pull_request_files_path(pull_request.repository.owner_display_login, pull_request.repository.name, pull_request.number)
      end
    end

    memoize def update_path
      pull_request_review_update_path(pull_request.repository.owner_display_login, pull_request.repository.name, pull_request.number, pull_request_review.id)
    end

    memoize def on_behalf_of_teams
      pull_request_review.prelude_on_behalf_of_visible_teams_for(current_user).sort_by(&:created_at)
    end

    def on_behalf_of
      team_links = on_behalf_of_teams.first(MAX_TEAMS_TO_DISPLAY).map do |team|
        link_to content_tag(:span, team.combined_slug, class: "Link--primary text-bold"), team.permalink(include_host: false).to_s, data: hovercard_data_attributes_for_team(team)
      end

      if on_behalf_of_teams.count > MAX_TEAMS_TO_DISPLAY
        other_count = on_behalf_of_teams.count - MAX_TEAMS_TO_DISPLAY
        team_links << pluralize(other_count, "other team")
      end

      html_safe_to_sentence(team_links)
    end

    def self.body_html_context(pull_request:, viewer:, cap_filter:, unfurl_references: false)
      {
        viewer: viewer,
        cap_filter: cap_filter,
        unfurl_references: unfurl_references,
      }
    end

    memoize def body_html
      context = self.class.body_html_context(
        pull_request: pull_request,
        viewer: current_user,
        cap_filter: cap_filter,
        unfurl_references: true
      )
      pull_request_review.prelude_body_html({ context: context }) || GitHub::HTMLSafeString::EMPTY
    end

    memoize def page_info
      pull_request_review.prelude_paginated_review_threads_and_replies_for(current_user, ReviewComponent.pagination_params)
    end

    def self.pagination_params
      { first: THREADS_TO_DISPLAY / 2, last: THREADS_TO_DISPLAY / 2 }.freeze
    end

    def action_menu_path
      review_comment_actions_path(
        tab: "discussion",
        user_id: pull_request.repository.owner_display_login,
        repository: pull_request.repository.name,
        id: pull_request_review.global_relay_id,
        pull_id: pull_request.number
      )
    end

    def render_minimized_header?
      pull_request_review.minimized? && !render_if_minimized
    end

    def show_path
      pull_request_review_path(pull_request.repository.owner, pull_request.repository, pull_request, pull_request_review)
    end

    def author_is_copilot?
      pull_request_review.copilot?
    end

    def empty_copilot_review?
      author_is_copilot? && pull_request_review.review_comments.empty?
    end
  end
end
