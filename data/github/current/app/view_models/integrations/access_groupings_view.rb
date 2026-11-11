# typed: true
# frozen_string_literal: true

class Integrations::AccessGroupingsView < AccessGroupings::ShowView

  sig { override.returns(Integration) }
  attr_reader :integration
  attr_reader :target

  # Internal: Memoize the permissions.
  #
  # Returns the organization and repository permission Hash
  def permissions
    return @permissions if defined?(@permissions)

    version = integration.latest_version

    @permissions = if target.present?
      version.permissions_relevant_to(target)
    else
      permissions = version.permissions_of_type(Organization)
      permissions.merge!(version.permissions_of_type(Repository))
      permissions.merge!(version.permissions_of_type(Business))
    end

    @permissions
  end

  # Internal: Memoize the permissions.
  #
  # Returns the user permission Hash
  def user_permissions
    @user_permissions ||= integration.latest_version.user_permissions
  end

  sig { override.returns(IntegrationVersion) }
  def current_version
    integration.latest_version
  end
end
