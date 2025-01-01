# typed: true
# frozen_string_literal: true

module Commits::ReactPayload
  def self.app_payload
    {
      helpUrl: GitHub.help_url,
    }
  end

  def self.feature_flags
    [:commits_ux_refresh_compare].freeze
  end
end
