# typed: false
# frozen_string_literal: true

require "csv"

class SurveyAnswer < ApplicationRecord::Domain::Surveys
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification

  belongs_to :choice, class_name: "SurveyChoice", foreign_key: "choice_id" # rubocop:todo Rails/InverseOf
  validates_presence_of :choice

  belongs_to :question, class_name: "SurveyQuestion", foreign_key: "question_id" # rubocop:todo Rails/InverseOf
  validates_presence_of :question

  validate :choice_must_belong_to_question

  belongs_to :survey
  validates_presence_of :survey

  belongs_to :user
  validates_presence_of :user

  belongs_to :survey_group

  after_create_commit :instrument_create

  scope :sponsors_organization_waitlist_survey, -> { joins(:survey).merge(Survey.sponsors_organization_waitlist) }
  scope :with_other_text, -> { where.not(other_text: nil).where.not(other_text: "") }

  def self.most_recent_first
    order(:id).reverse_order
  end

  scope :for, ->(user) { where(user_id: user) }
  scope :for_question, ->(question_id) { where(question_id: question_id) }
  scope :with_choice, -> (choice_id) { where(choice_id: choice_id) }

  # Internal: Instrument on after_create.
  def instrument_create
    instrument :create
  end

  def selections=(selections)
    selections = Array.wrap(selections.presence).sort
    self.other_text = CSV.generate_line(selections, row_sep: "")
  end

  def selections
    CSV.parse(other_text.to_s).first || Array.new
  end

  def normalized_other_text
    other_text.to_s.strip
  end

  # other_text is a varbinary column to support wide multibyte characters (like
  #   emoji..) however the value comes back as ASCII-8BIT, which can cause
  #   encoding mismatches
  def other_text
    text = self.read_attribute(:other_text)
    return text.dup.force_encoding("UTF-8") if text
    text
  end

  def self.save_as_group(user_id, survey_id, answers)
    SurveyGroup.transaction do
      group = SurveyGroup.create!({ survey_id: survey_id, user_id: user_id })
      (answers || []).map do |answer|
        SurveyAnswer.create!({
          user_id: user_id,
          survey_id: survey_id,
          survey_group_id: group.id,
          question_id: answer[:question_id],
          choice_id: answer[:choice_id],
          other_text: answer[:other_text]&.to_s&.slice(0, 3000),
        })
      end
      group
    end
  rescue ActiveRecord::RecordInvalid
    false
  end

  private

  # Default attributes for auditing
  def event_payload
    { survey_slug: survey.slug }
  end

  def choice_must_belong_to_question
    return if question_id == choice&.question_id
    errors.add(:choice, "is invalid for question")
  end
end
