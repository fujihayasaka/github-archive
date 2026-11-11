# typed: strict
# frozen_string_literal: true

module CodingToolsHelper
  extend T::Helpers

  requires_ancestor { Object }

  abstract!

  sig { abstract.returns(T.nilable(ActionDispatch::Request)) }
  def request; end

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  KNOWN_TOOLS = T.let(%w[
    copilot_vs_code
    claude_code_web
    codex_desktop_app
  ].freeze, T::Array[String])

  # Public: Returns whether the given coding tool is enabled via the
  # `preferred_coding_tools` cookie. Returns `false` when the
  # `coding_tool_settings` feature flag is disabled, for unknown
  # tools, or when the cookie is absent/malformed.
  sig { params(tool_name: String).returns(T::Boolean) }
  def coding_tool_enabled?(tool_name)
    return false unless FeatureFlag.vexi.enabled?(:coding_tool_settings, current_user, default: false)
    return false unless KNOWN_TOOLS.include?(tool_name)

    raw = request&.cookies&.[]("preferred_coding_tools")
    return false if raw.blank?

    parsed = JSON.parse(raw)
    parsed.is_a?(Hash) && parsed[tool_name] == true
  rescue JSON::ParserError
    false
  end
end
