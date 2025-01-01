# typed: true
# frozen_string_literal: true

module Sponsors
  class UserWaitlistSurvey
    extend T::Sig

    SLUG = "github_sponsors"

    sig { returns Survey }
    def self.find_or_create_survey
      survey = Survey.find_by(slug: SLUG) || Survey.create!(
        title: "GitHub Sponsored Developers waitlist",
        slug: SLUG,
      )

      project_profile_question = survey.questions.sponsors_fiscally_hosted_project_profile.first
      project_profile_question ||= survey.questions.create!(
        text: SponsorsListing::FiscalHostDependency::FISCALLY_HOSTED_PROJECT_PROFILE_QUESTION_TEXT,
        short_text: SponsorsListing::FiscalHostDependency::FISCALLY_HOSTED_PROJECT_PROFILE_QUESTION_SLUG,
        display_order: 1,
      )

      other_choice = project_profile_question.choices.other.first
      other_choice ||= project_profile_question.choices.create!(
        text: SurveyChoice::OTHER_TEXT,
        short_text: SurveyChoice::OTHER_SLUG,
      )

      survey
    end
  end
end
