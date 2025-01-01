# typed: true
# frozen_string_literal: true

class Api::Runtime::IntegrationChecker
  sig do
    params(
      current_user: User,
      current_integration: T.nilable(Integration),
      allowed_integration_names: T::Array[Symbol],
    ).void
  end
  def initialize(current_user, current_integration, allowed_integration_names)
    @current_user = current_user
    @current_integration = current_integration
    @allowed_integration_names = allowed_integration_names
  end

  sig do
    returns(T::Array[Integration])
  end
  def allowed_integrations
    @allowed_integration_names.map do |name|
      ::Apps::Privileged.integration(name)
    end.compact
  end

  sig do
    returns(T::Boolean)
  end
  def allowed?
    # Get out early if the user has been tagged to allow PAT access to Spark APIs
    # Should only allow internal use, as Spark on PATs needs more scope + permissions work to be allowed generally.
    return true if FeatureFlag.vexi.enabled?(:copilot_workbench_allow_pat_on_api, @current_user, default: false)

    # In development we run with a PAT from monalisa, so this check doesn't apply
    return true if Rails.env.development?

    # Get our supported integrations
    integrations = allowed_integrations

    GitHub.logger.info("Api::Runtime::IntegrationChecker#allowed?",
      current_integration: @current_integration&.id,
      allowed_integrations: integrations.map { |int| int.id },
    )

    # Now only allow if our current integration is in the list
    integrations.include?(@current_integration)
  end
end
