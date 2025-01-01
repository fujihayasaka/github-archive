# typed: true
# frozen_string_literal: true

module Copilot
  class CopilotForEnterpriseBetaWaitlistSurvey
    SURVEY_SLUG = "copilot_for_enterprise_beta_waitlist"

    def self.find_survey
      Survey.find_by(slug: SURVEY_SLUG)
    end

    def self.create_survey(dry_run:)
      survey = Survey.new(
        title: "GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} waitlist",
        slug: SURVEY_SLUG,
      )
      survey.save! unless dry_run

      q = survey.questions.build(
        text: "Which features are you excited about the most?",
        short_text: "copilot_for_enterprise_features",
        display_order: 1,
      )
      q.save! unless dry_run

      c1 = q.choices.build(text: "Conversational search and summmarization on internal documentation", short_text: "copilot_for_docs", display_order: 1)
      c1.save! unless dry_run
      c2 = q.choices.build(text: "Chat-based Copilot assistance in the GitHub Platform", short_text: "copilot_for_dotcom_chat", display_order: 0)
      c2.save! unless dry_run
      c3 = q.choices.build(text: "Skills for pull requests, including description generation and diff analysis", short_text: "copilot_for_prs", display_order: 2)
      c3.save! unless dry_run

      # This question is internal-only and will be filled in via the controller, not
      # by the user
      q2 = survey.questions.build(
        text: "Is admin",
        short_text: "is_admin",
        hidden: true,
        display_order: 2,
      )
      q2.save! unless dry_run

      c5 = q2.choices.build(text: "Yes", short_text: "is_admin")
      c5.save! unless dry_run
      c6 = q2.choices.build(text: "No", short_text: "is_end_user")
      c6.save! unless dry_run

      # This question is internal-only and will be filled in via the controller, not
      # by the user
      q3 = survey.questions.build(
        text: "Enterprise",
        short_text: "enterprise_slug",
        hidden: true,
        display_order: 3,
      )
      q3.save! unless dry_run
      c7 = q3.choices.build(text: "slug", short_text: "slug")
      c7.save! unless dry_run
      survey
    end

    def self.find_or_create_survey!
      find_survey || create_survey(dry_run: false)
    end
  end
end
