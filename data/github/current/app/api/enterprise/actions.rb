# typed: true
# frozen_string_literal: true

class Api::Enterprise::Actions < Api::App
  before do
    deliver_error! 404 unless GitHub.enterprise? && GitHub.actions_enabled?
  end

  # This is used for authenticating dotcom to Enterprise using an Enterprise
  # installation.
  post "/enterprise/actions-token", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/c2c-actions-experience"
    require_authentication!
    deliver_error! 404 unless GitHub::Connect.download_dotcom_actions_enabled?

    # Only let the Actions scoped tokens access this endpoint.
    deliver_error! 404 unless Apps::Internal.capable?(:access_enterprise_actions_token_api, app: current_integration)

    response = GitHub::Connect.create_dotcom_actions_download_token

    deliver_raw(GitHub::JSON.parse(response.body), status: response.status)
  end
end
