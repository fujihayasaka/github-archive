# typed: true
# frozen_string_literal: true

module Copilot
  class CustomizationBetaWaitlistSurvey
    # This survey record was already created in production before we renamed
    # custom models to customization and before we renamed customization to fine-tuning
    SLUG = "copilot_custom_models_beta_waitlist"

    def self.find_survey
      Survey.find_by(slug: SLUG)
    end

    def self.create_survey(dry_run:)
      survey = Survey.new(
        title: "GitHub Copilot Customization waitlist",
        slug: SLUG,
      )
      survey.save! unless dry_run

      # Preview specific terms is internal-only and will be filled in via the controller,
      # not by the user
      terms_q = survey.questions.build(
        text: "GitHub Copilot preview specific terms",
        short_text: "copilot_preview_specific_terms",
        hidden: true,
        display_order: 1,
      )
      terms_q.save! unless dry_run

      terms_c = terms_q.choices.build(
        text: "I accept the GitHub Copilot preview specific terms above",
        short_text: "agree_copilot_preview_specific_terms",
        display_order: 1,
      )
      terms_c.save! unless dry_run

      # This question is internal-only and will be filled in via the controller, not
      # by the user
      admin_q = survey.questions.build(
        text: "Is admin",
        short_text: "is_admin",
        hidden: true,
        display_order: 2,
      )
      admin_q.save! unless dry_run

      admin_c1 = admin_q.choices.build(text: "Yes", short_text: "is_admin")
      admin_c1.save! unless dry_run
      admin_c2 = admin_q.choices.build(text: "No", short_text: "is_end_user")
      admin_c2.save! unless dry_run

      # This question is internal-only and will be filled in via the controller, not
      # by the user
      org_q = survey.questions.build(
        text: "Organization",
        short_text: "organization_login",
        hidden: true,
        display_order: 3,
      )
      org_q.save! unless dry_run
      org_c = org_q.choices.build(text: "org_login", short_text: "org_login")
      org_c.save! unless dry_run

      survey
    end

    def self.find_or_create_survey!
      find_survey || create_survey(dry_run: false)
    end
  end
end
