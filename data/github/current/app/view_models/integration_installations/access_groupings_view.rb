# typed: true
# frozen_string_literal: true

class IntegrationInstallations::AccessGroupingsView < AccessGroupings::ShowView
  extend T::Sig

  attr_reader :integration_installation

  delegate :target, :version, to: :integration_installation

  sig { override.returns(Integration) }
  def integration
    T.must(integration_installation).integration
  end

  # Internal: Memoize the permissions.
  #
  # Returns the organization and repository permission Hash
  def permissions
    return @permissions if defined?(@permissions)
    @permissions = version.permissions_relevant_to(target)
  end

  # Internal: Memoize the permissions.
  #
  # Returns the user permission Hash
  def user_permissions
    @user_permissions ||= version.user_permissions
  end

  sig { override.returns(IntegrationVersion) }
  def current_version
    integration_installation.version
  end
end
