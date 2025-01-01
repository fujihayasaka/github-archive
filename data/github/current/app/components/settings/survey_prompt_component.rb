# typed: true
# frozen_string_literal: true

module Settings
  class SurveyPromptComponent < ApplicationComponent
    HIDE_FOR_DAYS = 90

    sig { returns(T::Boolean) }
    def render?
      if GitHub.enterprise?
        false
      elsif !logged_in?
        false
      elsif PushProtectionSurvey.taken_by?(current_user)
        false
      elsif PushProtectionSurvey.hidden_by?(current_user)
        false
      elsif !PushProtectionSurvey.disabled_by?(current_user)
        false
      else
        true
      end
    end

    private

    sig { returns(ActiveRecord::Associations::CollectionProxy) }
    memoize def questions
      T.unsafe(Survey).find_by_slug(PushProtectionSurvey::SLUG).questions
    end

    sig { returns(T.nilable(Integer)) }
    def reason_question_id
      question = questions.find { |q| q.short_text == "reason" }
      return -1 if question.nil?
      question.id
    end

    sig { returns(T.nilable(Integer)) }
    def elaborate_question_id
      question = questions.find { |q| q.short_text == "elaborate" }
      return -1 if question.nil?
      question.id
    end

    sig { returns(T::Array[[String, T.nilable(Integer), { name: String }]]) }
    def reason_options
      question = questions.find { |q| q.short_text == "reason" }
      return [] if question.nil?
      question.choices.map { |c| [c.text, c.id, { name: "answers[#{question.id}][choice]" }] }
    end

    sig { returns(T.nilable(Integer)) }
    def elaborate_choice_id
      question = questions.find { |q| q.short_text == "elaborate" }
      return -1 if question.nil?
      question.choices.first.id
    end
  end
end
