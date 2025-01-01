# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class BaseRefDeletedEventComponent < ApplicationComponent
    include PullRequestsHelper

    attr_reader :issue_event, :pull_request

    def initialize(issue_event:, pull_request:)
      @issue_event = issue_event
      @pull_request = pull_request
    end

    memoize def login
      base_repository_owner&.display_login
    end

    def display_login
      # this is safe for this rubocop rule since it refers to the memoized login method above, not User#login
      login.present? && pull_request.cross_repo? # rubocop:disable GitHub/DoNotAllowLogin, GitHub/DoNotAllowLoginInViewsAndViewModels
    end

    def ref_name
      ref = pull_request.display_base_ref_name
      # this is safe for this rubocop rule since it refers to the memoized login method above, not User#login
      display_login ? "#{login}:#{ref}" : ref # rubocop:disable GitHub/DoNotAllowLogin, GitHub/DoNotAllowLoginInViewsAndViewModels
    end

    def base_repository_owner
      pull_request.async_base_user.sync do |user|
        user&.spammy? ? nil : user
      end
    end
  end
end
