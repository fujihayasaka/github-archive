# typed: true
# frozen_string_literal: true

module Commit::ReactPayload
  def self.app_payload
    {
      helpUrl: GitHub.help_url,
    }
  end

  def self.feature_flags
    [:diff_ux_refresh_beta, :commit_details_extra_diff_fetching].freeze
  end
end
