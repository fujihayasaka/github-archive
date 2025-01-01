# typed: true
# frozen_string_literal: true

module BlackbirdMonolith
  class BetaWaitlistSurvey
    SURVEY_SLUG = "blackbird_monolith_waitlist"

    def self.find_survey
      Survey.find_by(slug: SURVEY_SLUG)
    end

    def self.create_survey(force: false)
      if force && survey = find_survey
        survey.destroy
      end

      survey = Survey.new(
        slug: SURVEY_SLUG,
        title: "Code Search And Code View Waitlist"
      )
      survey.save!
      survey
    end
  end
end
