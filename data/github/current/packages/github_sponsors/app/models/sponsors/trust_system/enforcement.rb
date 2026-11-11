# typed: true
# frozen_string_literal: true

module Sponsors::TrustSystem::Enforcement
  private

  def trust_enforced?(trust_target)
    !!trust_target&.feature_flag_enabled?(:sponsors_enforce_trust_system, default: false)
  end
end
