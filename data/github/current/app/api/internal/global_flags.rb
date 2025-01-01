# typed: true
# frozen_string_literal: true

# Retrieves a list of the globally enabled feature flags
class Api::Internal::GlobalFlags < Api::Internal
  def externally_accessible?
    true
  end

  def require_request_hmac?
    true
  end

  get "/internal/global_flags", operation_id: :internal do
    # Only enable this endpoint for github.com
    deliver_error! 404 unless GitHub.flavor == "GitHub"

    @route_owner = "@github/test-frameworks-reviewers"
    control_access :list_global_flags, resource: current_user, challenge: true, allow_integrations: false, allow_user_via_granular_actor: true

    deliver :global_feature_flags_hash, { flag_names: FlipperFeature.fully_enabled.pluck(:name) }
  end
end
