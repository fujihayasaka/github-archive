# typed: true
# frozen_string_literal: true

module Copilot
  class WorkspaceBeta
    include GitHub::Memoizer

    attr_reader :feature_slug, :feature_name, :waitlist,
                :survey, :preview_terms,
                :onboard_job, :bulk_onboard_batch_size
    FEATURE_NAME = "Copilot Workspace"
    BULK_ONBOARD_BATCH_SIZE = 50

    DetailLink = Struct.new(:text, :url, keyword_init: true)

    def initialize
      @feature_slug = "copilot_workspace"
      @feature_name = "#{FEATURE_NAME}"
      @waitlist = EarlyAccessMembership.copilot_workspace_waitlist
      @survey = Copilot::WorkspaceWaitlistSurvey.find_survey
      @preview_terms = DetailLink.new(
        text: "the GitHub Next pre-release terms",
        url: "https://github.com/githubnext/githubnext/blob/main/TERMS_AND_CONDITIONS.md"
      )
      @onboard_job = Copilot::WorkspaceBetaOnboardJob
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
