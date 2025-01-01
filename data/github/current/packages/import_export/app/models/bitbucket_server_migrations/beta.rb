# typed: true
# frozen_string_literal: true

module BitbucketServerMigrations
  class Beta
    attr_reader :feature_slug, :feature_name, :feature_url, :feature_icon_path,
      :sign_up_callout, :sign_up_feature_flag, :waitlist, :survey, :onboard_job

    def initialize
      @feature_slug = "octoshift_bitbucket_server"
      @feature_name = "Bitbucket Server migrations"
      @feature_url = "https://github.com/github/octoshift"
      @sign_up_callout = "Register your interest to start migrating your repositories and pull requests from Bitbucket Server to GitHub.com. Access is limited during the private beta, and we may not give you access immediately."
      @sign_up_feature_flag = :bitbucket_server_migrations_signup
      @waitlist = EarlyAccessMembership.bitbucket_server_migrations_waitlist
      @survey = BitbucketServerMigrations::WaitlistSurvey.find_survey
      @onboard_job = BitbucketServerMigrationsOnboardWaitlistUserJob
    end

    def only_show_onboardable_members?
      true
    end
  end
end
