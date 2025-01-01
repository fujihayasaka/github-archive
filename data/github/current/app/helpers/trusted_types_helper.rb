# typed: true
# frozen_string_literal: true

module TrustedTypesHelper
  extend T::Helpers
  requires_ancestor { ApplicationController }

  ENFORCE_TRUSTED_TYPES_CONFIG = {
    preserve_schemes: !GitHub.ssl?,
    require_trusted_types_for: GitHub::CSP::Policy::REQUIRE_TRUSTED_TYPES_FOR_SINK_GROUPS,
    trusted_types: GitHub::CSP::Policy::TRUSTED_TYPES_POLICIES
  }

  def trusted_types_enforce_via_param
    return if GitHub.enterprise?
    return unless current_user&.preview_features?
    return unless params[:trusted_types_enforce] == "1"
    SecureHeaders.append_content_security_policy_directives(request, ENFORCE_TRUSTED_TYPES_CONFIG)
  end
end
