# typed: true
# frozen_string_literal: true

module Repositories
  class SurveyComponent < ApplicationComponent
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

    def required?(question)
      %w[file_browsing file_editing branch_creation general_satisfaction].include?(question.short_text)
    end
  end
end
