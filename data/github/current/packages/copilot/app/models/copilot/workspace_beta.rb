# typed: true
# frozen_string_literal: true

module Copilot
  class WorkspaceBeta
    include GitHub::Memoizer

    attr_reader :feature_slug, :feature_name, :waitlist,
                :survey, :preview_terms,
                :onboard_job, :bulk_onboard_batch_size
    FEATURE_NAME = "Copilot Workspace"
    BULK_ONBOARD_BATCH_SIZE = 500

    DetailLink = Struct.new(:text, :url, keyword_init: true)

    def initialize
      @feature_slug = "copilot_workspace"
      @feature_name = "#{FEATURE_NAME}"
      @waitlist = EarlyAccessMembership.copilot_workspace_waitlist
      @survey = Copilot::WorkspaceWaitlistSurvey.find_survey
      @preview_terms = DetailLink.new(
        text: "the GitHub Next pre-release terms",
        url: Copilot::GITHUB_NEXT_TERMS
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

    def only_show_onboardable_members?
      true
    end
  end
end
