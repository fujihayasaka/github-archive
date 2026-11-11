# typed: strict
# frozen_string_literal: true

module Sponsors
  class OrganizationWaitlistSurvey
    SLUG = "github_sponsors_organizations"

    sig { returns Survey }
    def self.find_or_create_survey
      survey = Survey.find_by(slug: SLUG)
      return survey if survey

      display_order = 0
      survey = Survey.create!(title: "GitHub Sponsored Organizations waitlist", slug: SLUG)

      project_profile_question = survey.questions.create!(
        text: SponsorsListing::FiscalHostDependency::FISCALLY_HOSTED_PROJECT_PROFILE_QUESTION_TEXT,
        short_text: SponsorsListing::FiscalHostDependency::FISCALLY_HOSTED_PROJECT_PROFILE_QUESTION_SLUG,
        display_order: (display_order += 1),
      )
      project_profile_question.choices.create!(text: SurveyChoice::OTHER_TEXT, short_text: SurveyChoice::OTHER_SLUG)

      survey
    end
  end
end
