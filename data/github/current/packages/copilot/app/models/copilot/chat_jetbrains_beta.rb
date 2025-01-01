# typed: true
# frozen_string_literal: true

module Copilot
  class ChatJetbrainsBeta
    include GitHub::Memoizer

    attr_reader :feature_slug, :feature_name, :waitlist,
                :survey, :preview_terms,
                :onboard_job, :bulk_onboard_batch_size
    FEATURE_NAME = "Copilot Chat in JetBrains IDEs"
    BULK_ONBOARD_BATCH_SIZE = 5_000

    DetailLink = Struct.new(:text, :url, keyword_init: true)

    def initialize
      @feature_slug = "copilot_chat_jetbrains"
      @feature_name = "#{FEATURE_NAME}"
      @waitlist = EarlyAccessMembership.copilot_chat_jetbrains_waitlist
      @survey = Copilot::ChatJetbrainsBetaWaitlistSurvey.find_survey
      @preview_terms = DetailLink.new(
        text: "the pre-release terms",
        url: "https://docs.github.com/site-policy/github-terms/github-copilot-pre-release-license-terms"
      )
      @onboard_job = Copilot::ChatJetbrainsBetaOnboardJob
      @bulk_onboard_batch_size = BULK_ONBOARD_BATCH_SIZE
    end

    def extra_columns(_memberships)
      [
        {
          header: "Plan type",
          get_content: ->(member) { member.plan.name.humanize }
        },
      ]
    end

    def only_show_onboardable_members?
      true
    end
  end
end
