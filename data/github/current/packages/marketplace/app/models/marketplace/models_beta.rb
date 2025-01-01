# typed: true
# frozen_string_literal: true

class Marketplace::ModelsBeta
  attr_reader :feature_slug, :feature_name, :waitlist,
              :survey, :preview_terms,
              :onboard_job, :bulk_onboard_batch_size
  FEATURE_NAME = "GitHub Models"
  BULK_ONBOARD_BATCH_SIZE = 500 # This controls the batch size in the stafftools

  DetailLink = Struct.new(:text, :url, keyword_init: true)

  def initialize
    # this is the slug that the waitlist uses - anyone enabled in the waitlist gets access via the early_access_enabled
    @feature_slug = "project_neutron_playground"
    @feature_name = "#{FEATURE_NAME}"
    # this is a scope on the EarlyAccessMembership for the onboard_job
    @waitlist = EarlyAccessMembership.project_neutron_playground_waitlist
    # all waitlists need a survey - this just has an "i accept the tos" 'question'
    @survey = Marketplace::ModelsBetaWaitlistSurvey.find_survey
    @preview_terms = DetailLink.new(
      text: "GitHub's preview terms",
      url: "https://docs.github.com/site-policy/github-terms/github-pre-release-license-terms"
    )
    @onboard_job = ModelsBetaOnboardJob
    @bulk_onboard_batch_size = BULK_ONBOARD_BATCH_SIZE
  end
end
