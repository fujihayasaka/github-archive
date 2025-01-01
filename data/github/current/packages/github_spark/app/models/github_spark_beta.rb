# typed: true
# frozen_string_literal: true

class GitHubSparkBeta
  include GitHub::Memoizer

  attr_reader :feature_slug, :feature_name, :waitlist,
              :survey, :preview_terms,
              :onboard_job, :bulk_onboard_batch_size
  FEATURE_NAME = "GitHub Spark"
  BULK_ONBOARD_BATCH_SIZE = 50

  DetailLink = Struct.new(:text, :url, keyword_init: true)

  def initialize
    @feature_slug = "github_spark"
    @feature_name = "#{FEATURE_NAME}"
    @waitlist = EarlyAccessMembership.github_spark_waitlist
    @survey = GitHubSparkWaitlistSurvey.find_survey
    @preview_terms = DetailLink.new(
      text: "the GitHub Next pre-release terms",
      url: Copilot::GITHUB_NEXT_TERMS
    )
    @onboard_job = GitHubSparkBetaOnboardJob
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
