# typed: true
# frozen_string_literal: true

module BlackbirdMonolith
  class Beta
    attr_reader :feature_slug, :feature_name, :feature_url, :feature_icon_path,
      :sign_up_callout, :sign_up_feature_flag, :waitlist, :survey, :onboard_job

    def initialize
      @feature_slug = "code_search_code_view"
      @feature_name = "Code Search and Code View"
      @feature_url = "https://github.com/search"
      @sign_up_callout = "Access is limited during the public beta. Sign up today for your chance to try it and share your feedback."
      @sign_up_feature_flag = :code_search_code_view_signup
      @waitlist = EarlyAccessMembership.code_search_code_view_waitlist
      @survey = BlackbirdMonolith::BetaWaitlistSurvey.find_survey
      @onboard_job = CodeSearchCodeViewOnboardJob
    end

    def only_show_onboardable_members?
      true
    end
  end
end
