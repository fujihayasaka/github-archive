# typed: false
# frozen_string_literal: true

module SignupAnalyticsHelper
  module SignupInterstitialClick
    module Target
      CREATE_REPO_BUTTON = :CREATE_REPO_BUTTON
      CREATE_ORG_BUTTON = :CREATE_ORG_BUTTON
      LEARNING_LAB_BUTTON = :LEARNING_LAB_BUTTON
      SKIP_BUTTON = :SKIP_BUTTON
    end
  end

  def signup_cta_button_attributes(event_target)
    event_targets = {
      create_repo: SignupInterstitialClick::Target::CREATE_REPO_BUTTON,
      create_org: SignupInterstitialClick::Target::CREATE_ORG_BUTTON,
      learning_lab: SignupInterstitialClick::Target::LEARNING_LAB_BUTTON,
      skip: SignupInterstitialClick::Target::SKIP_BUTTON,
    }

    hydro_click_tracking_attributes("signup_interstitial.click",
      event_target: event_targets[event_target],
    )
  end
end
