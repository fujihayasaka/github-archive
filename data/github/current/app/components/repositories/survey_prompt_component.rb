# typed: false
# frozen_string_literal: true

module Repositories
  class SurveyPromptComponent < ApplicationComponent
    attr_reader :user, :repository
    def initialize(user:, repository:)
      @user = user
      @repository = repository
    end

    def render?
      user && survey && Repository::Survey.show_survey_prompt_for_user?(user)
    end

    memoize def survey
      Survey.find_by_slug(Repository::Survey::SURVEY_SLUG)
    end
  end
end
