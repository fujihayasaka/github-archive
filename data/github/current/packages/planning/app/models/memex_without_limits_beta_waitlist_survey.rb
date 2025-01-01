# typed: strict
# frozen_string_literal: true

class MemexWithoutLimitsBetaWaitlistSurvey
  extend T::Sig

  SURVEY_SLUG = T.let("memex_without_limits_beta_waitlist", String)

  SURVEY_TITLE = T.let("Memex Without Limits Beta Waitlist", String)

  sig { returns(T.nilable(Survey)) }
  def self.find_or_create_survey
    Survey.find_by(slug: SURVEY_SLUG) || create_survey
  end

  # Public: Creates the Memex Without Limits beta waitlist survey.
  sig { returns(Survey) }
  def self.create_survey
    survey = Survey.new(
      slug: SURVEY_SLUG,
      title: SURVEY_TITLE
    )
    survey.save!
    survey
  end
end
