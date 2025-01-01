# typed: true
# frozen_string_literal: true

module PullRequests
  class SurveyPromptComponent < ApplicationComponent
    attr_reader :user, :repository
    def initialize(user:, repository:)
      @user = user
      @repository = repository
    end

    def render?
      return false unless user
      return false unless survey
      return false unless PullRequest::Survey.in_current_survey?(user)
      if GitHub.enterprise?
        false
      elsif PullRequest::Survey.new_user?(user)
        false
      elsif survey.taken_by?(user)
        false
      elsif PullRequest::Survey.hidden_by?(user)
        false
      else
        true
      end
    end

    memoize def survey
      Survey.find_by(slug: PullRequest::Survey::SLUG)
    end
  end
end
