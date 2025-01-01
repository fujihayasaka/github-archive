# typed: true
# frozen_string_literal: true

module Copilot
  class CustomizationBeta
    include GitHub::Memoizer

    attr_reader :feature_slug, :feature_name, :waitlist,
                :survey, :preview_terms, :onboard_job
    FEATURE_NAME = "Copilot Fine-tuning"

    DetailLink = Struct.new(:text, :url, keyword_init: true)

    def initialize
      @feature_slug = "copilot_customization"
      @feature_name = "#{FEATURE_NAME}"
      @waitlist = EarlyAccessMembership.copilot_customization_waitlist
      @survey = Copilot::CustomizationBetaWaitlistSurvey.find_survey
      @preview_terms = DetailLink.new(
        text: "the pre-release terms",
        url: "https://docs.github.com/site-policy/github-terms/github-copilot-pre-release-license-terms"
      )
      @onboard_job = Copilot::CustomizationBetaOnboardJob
    end

    def extra_columns(memberships)
      @cfb_seats_counts ||= begin
        user_ids = memberships.pluck(:member_id)
        Copilot::Seat.where(assigned_user_id: user_ids)
                     .group(:assigned_user_id)
                     .count
      end

      [
        {
          header: "Plan type",
          get_content: ->(member) { member.plan.name.humanize }
        },
        {
          header: "# of active CfB seats",
          get_content: ->(member) { @cfb_seats_counts[member.id] || 0 }
        },
      ]
    end

    def only_show_onboardable_members?
      true
    end
  end
end
