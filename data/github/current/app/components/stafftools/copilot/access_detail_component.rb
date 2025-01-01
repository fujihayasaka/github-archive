# typed: true
# frozen_string_literal: true

class Stafftools::Copilot::AccessDetailComponent < ApplicationComponent
  attr_reader :access_allowed, :allow_public_code_suggestions, :public_code_suggestions_configured, :copilot_access, :reason, :telemetry_enabled, :limited_user, :copilot_quotas_remaining

  def initialize(access_allowed: false, access_reason: nil, allow_public_code_suggestions: nil, public_code_suggestions_configured: nil, telemetry_enabled: nil, limited_user: nil, copilot_quotas_remaining: {})
    @allow_public_code_suggestions      = allow_public_code_suggestions
    @copilot_access                     = access_allowed
    @limited_user                       = limited_user
    @copilot_quotas_remaining           = copilot_quotas_remaining
    @public_code_suggestions_configured = public_code_suggestions_configured
    @reason                             = access_reason
    @telemetry_enabled                  = telemetry_enabled
  end
end
