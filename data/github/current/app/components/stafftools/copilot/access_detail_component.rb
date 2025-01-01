# typed: true
# frozen_string_literal: true

class Stafftools::Copilot::AccessDetailComponent < ApplicationComponent
  attr_reader :access_allowed, :access_reason, :allow_public_code_suggestions, :copilot_access, :reason, :telemetry_enabled

  def initialize(access_allowed: false, access_reason: nil, allow_public_code_suggestions: nil, telemetry_enabled: nil)
    @copilot_access                = access_allowed
    @reason                        = access_reason
    @allow_public_code_suggestions = allow_public_code_suggestions
    @telemetry_enabled             = telemetry_enabled
  end
end
