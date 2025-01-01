# typed: true
# frozen_string_literal: true

class MoveActorTypeToEnumOnPermissions < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Permissions)

  ACTOR_TYPES = %w(
    IntegrationInstallation
    OauthAuthorization
    OrganizationProgrammaticAccessGrant
    OrganizationProgrammaticAccessGrantRequest
    ScopedIntegrationInstallation
    SiteScopedIntegrationInstallation
    User
    UserProgrammaticAccessGrant
    UserProgrammaticAccessGrantRequest
  ).freeze

  def change
    change_table(:permissions, bulk: true) do |t|
      actor_types = ACTOR_TYPES.map { |type| "'#{type}'" }.join(",")
      t.change :actor_type, "enum(#{actor_types})", null: false
    end
  end
end
