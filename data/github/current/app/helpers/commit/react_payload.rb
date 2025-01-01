# typed: true
# frozen_string_literal: true

module Commit::ReactPayload
  def self.app_payload
    {
      helpUrl: GitHub.help_url,
    }
  end

  def self.feature_flags
    [].freeze
  end
end
