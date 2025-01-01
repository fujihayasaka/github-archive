# typed: true
# frozen_string_literal: true

module PullRequests
  class SurveyComponent < ApplicationComponent
    attr_reader :survey, :questions, :return_to, :user, :repository

    def initialize(survey:, return_to: nil, user:, repository:)
      @survey = survey
      @questions = survey.questions.includes(:choices).order(:display_order)
      @return_to = return_to
      @user = user
      @repository = repository
    end

    def freeform?(question)
      question.short_text == "anything-else"
    end

    def required?(question)
      question.short_text == "satisfaction"
    end
  end
end
