# typed: true
# frozen_string_literal: true

module Copilot
  class NextEditSuggestionsBeta
    include GitHub::Memoizer

    attr_reader :feature_slug, :feature_name, :waitlist,
                :survey, :preview_terms,
                :onboard_job, :bulk_onboard_batch_size
    FEATURE_NAME = "Copilot Next Edit Suggestions (NES)"
    BULK_ONBOARD_BATCH_SIZE = 5_000

    DetailLink = Struct.new(:text, :url, keyword_init: true)

    def initialize
      @feature_slug = "copilot_next_edit_suggestions"
      @feature_name = "#{FEATURE_NAME}"
      @waitlist = EarlyAccessMembership.copilot_next_edit_suggestions_waitlist
      @survey = Copilot::NextEditSuggestionsWaitlistSurvey.find_survey
      @preview_terms = DetailLink.new(
        text: "the GitHub Next pre-release terms",
        url: "https://github.com/githubnext/githubnext/blob/main/TERMS_AND_CONDITIONS.md"
      )
      @onboard_job = Copilot::NextEditSuggestionsBetaOnboardJob
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
  end
end
