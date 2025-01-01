# typed: true
# frozen_string_literal: true

module Commit::ReactPayload
  def self.app_payload
    {
      helpUrl: GitHub.help_url,
    }
  end

  def self.feature_flags
    [
      :diff_ux_refresh_beta,
      :diff_inline_comments,
      :diff_ux_refresh_ssr_five,
      :diff_ux_refresh_ssr_ten,
      :react_diff_line_type_character_correction,
    ].freeze
  end
end
