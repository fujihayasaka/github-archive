# typed: true
# frozen_string_literal: true

module BlackbirdSearch
  class Beta
    attr_reader :feature_slug, :feature_name, :feature_url, :feature_icon_path,
      :sign_up_callout, :sign_up_feature_flag, :waitlist, :survey, :onboard_job

    def initialize
      @feature_slug = "blackbird_fe"
      @feature_name = "GitHub Code Search"
      @feature_url = "https://cs.github.com"
      @sign_up_callout = "Access is limited during the technology preview of GitHub’s future code search. Sign up today for your chance to try it and give your feedback."
      @sign_up_feature_flag = :blackbird_sign_up
      @waitlist = EarlyAccessMembership.blackbird_waitlist
      @survey = BlackbirdSearch::BetaWaitlistSurvey.find_survey
      @onboard_job = BlackbirdOnboardJob
    end

    def only_show_onboardable_members?
      true
    end
  end
end
