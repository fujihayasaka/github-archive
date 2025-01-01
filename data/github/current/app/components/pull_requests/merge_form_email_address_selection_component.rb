# typed: true
# frozen_string_literal: true

module PullRequests
  class MergeFormEmailAddressSelectionComponent < ApplicationComponent
    attr_reader :pull_request, :user_emails

    def initialize(pull_request:, current_user:)
      @pull_request = pull_request
      @user_emails = current_user.author_emails
    end

    def current_user_is_author?
      current_user == pull_request.user
    end

    def has_multiple_emails?
      user_emails.any?
    end

    memoize def default_email
      current_user.default_author_email(pull_request.repository, pull_request.head_sha)
    end
  end
end
