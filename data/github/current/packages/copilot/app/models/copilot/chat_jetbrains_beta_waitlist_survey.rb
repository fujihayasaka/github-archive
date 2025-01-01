# typed: true
# frozen_string_literal: true

module Copilot
  class ChatJetbrainsBetaWaitlistSurvey
    SLUG = "copilot_chat_jetbrains_beta_waitlist"

    def self.find_survey
      Survey.find_by(slug: SLUG)
    end

    def self.create_survey(dry_run:)
      survey = Survey.new(
        title: "GitHub Copilot Chat in JetBrains IDEs waitlist",
        slug: SLUG,
      )
      survey.save! unless dry_run

      # Preview specific terms
      terms_q = survey.questions.build(
        text: "GitHub Copilot preview specific terms",
        short_text: "copilot_preview_specific_terms",
        display_order: 1,
      )
      terms_q.save! unless dry_run

      terms_c = terms_q.choices.build(
        text: "I accept the GitHub Copilot preview specific terms above",
        short_text: "agree_copilot_preview_specific_terms",
        display_order: 1,
      )
      terms_c.save! unless dry_run

      survey
    end

    def self.find_or_create_survey!
      find_survey || create_survey(dry_run: false)
    end
  end
end
