# typed: true
# frozen_string_literal: true

class SurveyQuestion < ApplicationRecord::Domain::Surveys
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations

  MAX_ANSWERS = { github_plans: 3, org_next_seven_days: 3 }
  ACCEPT_MULTIPLE_ANSWERS = %w[
    codesearch_preferred_search_features
    codesearch_contexts
    github_plans
    org_creator_role
    org_existing_repo_source
    org_existing_repo_source
    org_next_seven_days
    org_purpose
    planned_uses
    job_role_other
    copilot_chat
    primary_editor
  ]

  belongs_to :survey, required: true

  # rubocop:todo Rails/InverseOf
  has_many :choices,
    -> { where(active: true).order(:display_order) },
    class_name: "SurveyChoice",
    foreign_key: "question_id"
  # rubocop:enable Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  has_one :first_choice,
    -> { where(active: true).order(:display_order) },
    class_name: "SurveyChoice",
    foreign_key: "question_id"
  # rubocop:enable Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  has_many :active_and_inactive_choices,
    class_name: "SurveyChoice",
    foreign_key: "question_id",
    dependent: :destroy
  # rubocop:enable Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  has_many :answers, class_name: "SurveyAnswer", foreign_key: "question_id", dependent: :destroy
  # rubocop:enable Rails/InverseOf

  validates :text, presence: true, allow_blank: true, unicode3: true
  validates :short_text, presence: true, allow_blank: true, unicode3: true

  scope :hidden,  -> { where(hidden: true) }
  scope :visible, -> { where("hidden IS NOT true") }
  scope :sponsors_fiscally_hosted_project_profile, -> do
    where(short_text: SponsorsListing::FiscalHostDependency::FISCALLY_HOSTED_PROJECT_PROFILE_QUESTION_SLUG)
  end

  # Public: Whether or not the question has multiple choices.
  # Returns a Boolean.
  def multiple_choice?
    choices.many?
  end

  def other_choice
    choices.find { |choice| choice.other? }
  end

  def other_choice_id
    other_choice.try(:id)
  end

  # Public: Returns a summary of 'other_text' answers.
  # Removes duplicates and empty responses.
  #
  #   limit - An Integer to limit the number of answers scanned.
  #
  # Returns an Array<String>.
  def other_answers_summary(limit: 2000)
    return nil unless other_choice

    other_choice.answers.most_recent_first.
      limit(limit).
      collect(&:normalized_other_text).
      reject(&:blank?).
      uniq(&:downcase).
      sort
  end

  # Choices without a `display_order` are randomly placed at the begining of
  # the array. Choices with a `display_order` are sorted by that value and
  # placed at the end of the array.
  #
  # Returns the shuffled Array
  def shuffled_choices
    choices.sort_by { |choice| choice.display_order || rand }
  end

  def summarized_answers
    answers = SurveyChoice.connection.select_rows(Arel.sql(<<-SQL, question_id: id))
      SELECT survey_choices.text, COUNT(survey_answers.id) AS answer_count
      FROM survey_choices
      LEFT OUTER JOIN survey_answers ON survey_answers.choice_id = survey_choices.id
      WHERE survey_choices.question_id = :question_id
      GROUP BY survey_choices.id
    SQL

    total_answer_count = answers.sum { |_, answer_count| answer_count }.to_f

    answers.map do |text, answer_count|
      percent = if total_answer_count > 0
        ((answer_count / total_answer_count) * 100).round
      else
        0
      end
      {
        text: text,
        percent: percent,
        answer_count: answer_count
      }
    end
  end

  # Public: Whether or not you can submit several answers
  # for a single question. Useful for checkbox fields.
  #
  # Returns a Boolean.
  def accept_multiple_answers?
    ACCEPT_MULTIPLE_ANSWERS.include? short_text
  end

  # Public: State how many answers a question allows. Some questions allow a
  # user to select all that apply, so we set an arbitrarily high number to
  # indicate that.
  #
  # Returns an Integer.
  def max_acceptable_answers
    return 1 unless accept_multiple_answers?
    return 100_000 if MAX_ANSWERS[short_text.to_sym].nil?

    MAX_ANSWERS[short_text.to_sym]
  end
end
