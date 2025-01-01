# typed: true
# frozen_string_literal: true

class Marketplace::SearchOptions
  attr_reader :category_slug, :query, :tool_type, :verification_state, :copilot_app

  LISTING_TYPES = %w(copilot_apps apps actions)
  VERIFICATION_STATES = %w(verified unverified verified_creator)

  VERIFICATION_STATES_APP_MIGRATION = %w(verified_creator)

  alias_method :copilot_app?, :copilot_app

  def initialize(category_slug: nil, query: nil, tool_type: nil, verification_state: nil, copilot_app: nil)
    @category_slug = category_slug
    @query = query
    @tool_type = tool_type
    @verification_state = verification_state
    @copilot_app = copilot_app
  end

  def self.find_normalized_verification_state(raw_verification_state)
    VERIFICATION_STATES.find { |state| state == raw_verification_state.to_s.downcase }
  end

  def as_params(overrides = {})
    {
      category: category_slug,
      query: query,
      type: tool_type,
      verification: verification_state,
      copilot_app: copilot_app,
    }.merge(overrides).compact
  end
end
