# typed: true
# frozen_string_literal: true

module ClientEnvHelper
  include ActionView::Helpers::TagHelper
  include ERB::Util
  include FeatureFlagHelper

  def client_env(app_specific_flags: [])
    # NOTE: This env is sent on every hard page load and request to Alloy for React SSR
    # It should be used for env which is only available on the server, and is generally needed
    # across the site. If you have env that is only needed for a single React app/route, please
    # consider putting it in the React payload instead.
    @client_env ||= {
      locale: I18n.locale,
      featureFlags: client_side_feature_flags(app_specific_flags: app_specific_flags),
      login: T.unsafe(self).current_user&.display_login,
    }.compact
  end

  def client_env_script_tag
    content_tag(
      :script,
      json_escape(client_env.to_json).html_safe, # rubocop:disable Rails/OutputSafety
      type: "application/json",
      id: "client-env"
    )
  end
end
