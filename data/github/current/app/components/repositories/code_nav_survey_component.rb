# typed: true
# frozen_string_literal: true

module Repositories
  class CodeNavSurveyComponent < ApplicationComponent
    attr_reader :survey, :questions, :return_to, :user, :repository

    def initialize(survey:, return_to:, user:, repository:)
      @questions = survey.questions.includes(:choices).order(:display_order)
      @return_to = return_to
      @user = user
      @repository = repository
    end

    def freeform?(question)
      question.short_text == "additional_feedback"
    end

    def email?(question)
      question.short_text == "email"
    end

    def react_flag_state?(question)
      question.short_text == "react_repos_code_view"
    end

    def required?(question)
      ["code_navigation"].include?(question.short_text)
    end
  end
end
