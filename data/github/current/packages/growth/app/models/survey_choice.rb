# typed: true
# frozen_string_literal: true

class SurveyChoice < ApplicationRecord::Domain::Surveys # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations

  OTHER_SLUG = "other"
  OTHER_TEXT = "Other"

  belongs_to :question, class_name: "SurveyQuestion", required: true
  # rubocop:todo Rails/InverseOf
  has_many :answers, class_name: "SurveyAnswer", foreign_key: "choice_id", dependent: :destroy
  # rubocop:enable Rails/InverseOf

  validates :short_text, presence: true, allow_blank: true, unicode3: true
  validates :text, presence: true, allow_blank: true, unicode3: true

  scope :other, -> { where(short_text: OTHER_SLUG) }
  scope :for_question, ->(question_id) { where(question_id: question_id) }

  scope :with_answers_count, lambda {
    select("survey_choices.*, COUNT(survey_answers.id) AS num_of_answers")
      .joins("LEFT JOIN survey_answers ON survey_answers.choice_id = survey_choices.id
        LEFT JOIN survey_questions ON survey_questions.id = survey_choices.question_id")
      .order("display_order")
      .group("survey_choices.id")
  }

  def other?
    text =~ /\A#{OTHER_TEXT}(\b|$)/i
  end
end
