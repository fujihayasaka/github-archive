# typed: true
# frozen_string_literal: true

class Api::Enterprise::Tokens < Api::App
  def attempt_login
    assertion = Api::IntegrationAssertion.new(env)
    deliver_error! 404 unless assertion.valid?

    self.current_integration = assertion.integration
  end

  post "/enterprise/tokens", operation_id: :internal do
    @route_owner = "@github/dsp-dependabot-engineering"
    deliver_error! 404 unless valid_dependabot_request?

    control_access :create_permissionless_installation_token,
      allow_integrations: true,
      allow_user_via_granular_actor: false,
      resource: current_integration

    response = GitHub::Connect.create_dotcom_permissionless_installation_token
    deliver_raw(GitHub::JSON.parse(response.body), status: response.status)
  rescue GitHub::Connect::NotInstalled
    deliver_error! 404
  end

  private

  def valid_dependabot_request?
    return false if current_integration.blank?

    current_integration.dependabot_github_app? &&
      GitHub::Connect.dependabot_access_to_dotcom_enabled?
  end
end
