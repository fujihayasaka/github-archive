# typed: true
# frozen_string_literal: true

class Api::Status < Api::App

  get "/status", operation_id: :internal, skip_rate_limit: true do
    @route_owner = "@github/api-platform"
    control_access :public_site_information, resource: Platform::PublicResource.new, allow_integrations: true, allow_user_via_granular_actor: true # rubocop:disable GitHub/PublicResource
    cache_control "no-cache"

    payload = {
      message: "GitHub lives! (#{Time.now}) (1)",
    }
    deliver_raw payload
  end

  # This is a special case where we want to allow access to the status endpoint
  # It leaks no information, and is used by health checks
  def tenant_verification_enforceable
    :no
  end
end
