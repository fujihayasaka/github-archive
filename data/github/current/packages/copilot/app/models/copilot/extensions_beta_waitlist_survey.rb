# typed: strict
# frozen_string_literal: true

module Copilot
  class ExtensionsBetaWaitlistSurvey
    SURVEY_SLUG = "copilot_extensions_beta_waitlist"

    sig { returns(T.nilable(Survey)) }
    def self.find_survey
      Survey.find_by(slug: SURVEY_SLUG)
    end

    sig { params(dry_run: T::Boolean).returns(Survey) }
    def self.create_survey(dry_run:)
      ActiveRecord::Base.connected_to(role: :writing) do
        survey = Survey.new(
          title: "GitHub Copilot Extensions waitlist",
          slug: SURVEY_SLUG,
        )
        survey.save! unless dry_run

        # This question is internal-only and will be filled in via the controller, not by the user
        q1 = survey.questions.build(
          text: "Is admin",
          short_text: "is_admin",
          hidden: true,
          display_order: 1,
        )
        q1.save! unless dry_run

        c1 = q1.choices.build(text: "Yes", short_text: "is_admin")
        c1.save! unless dry_run
        c2 = q1.choices.build(text: "No", short_text: "is_end_user")
        c2.save! unless dry_run

        # This question is internal-only and will be filled in via the controller, not by the user
        q2 = survey.questions.build(
          text: "Member slug",
          short_text: "member_slug",
          hidden: true,
          display_order: 2,
        )
        q2.save! unless dry_run
        c3 = q2.choices.build(text: "slug", short_text: "slug")
        c3.save! unless dry_run

        # This question is internal-only and will be filled in via the controller, not by the user
        q3 = survey.questions.build(
          text: "Member type",
          short_text: "member_type",
          hidden: true,
          display_order: 3,
        )
        q3.save! unless dry_run
        c4 = q3.choices.build(text: "type", short_text: "type")
        c4.save! unless dry_run
        survey
      end
    end

    sig { returns(Survey) }
    def self.find_or_create_survey!
      find_survey || create_survey(dry_run: false)
    end
  end
end
