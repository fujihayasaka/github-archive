# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    # deletes old FGP, role, and role_permission because we renamed them
    class RemoveCustomPropertiesSchemaManagerFgp < Base
      FGP_ACTION = T.let("manage_org_custom_properties_schema".freeze, String)
      ROLE_NAME = T.let("custom_properties_org_schema_manager".freeze, String)

      sig { override.void }
      def perform
        if role_permission = RolePermission.find_by(action: FGP_ACTION)
          if dry_run?
            log "would delete role permission with action #{role_permission.action} and ID #{role_permission.id}"
          else
            log "deleting role permission with action #{role_permission.action} and ID #{role_permission.id}"
            write_to(model_class: RolePermission) do
              role_permission.destroy! unless dry_run?
            end
          end
        else
          log "could not find role permission to delete"
        end

        if role = Role.find_by(name: ROLE_NAME)
          if dry_run?
            log "would delete role with name #{role.name} and ID #{role.id}"
          else
            log "deleting role with name #{role.name} and ID #{role.id}"
            write_to(model_class: Role) do
              role.destroy!
            end
          end
        else
          log "could not find role to delete"
        end

        if fgp = FineGrainedPermission.find_by(action: FGP_ACTION)
          if dry_run?
            log "would delete fgp with action #{fgp.action} and ID #{fgp.id}"
          else
            log "deleting fgp with action #{fgp.action} and ID #{fgp.id}"
            write_to(model_class: FineGrainedPermission) do
              fgp.destroy! unless dry_run?
            end
          end
        else
          log "could not find fgp to delete"
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::RemoveCustomPropertiesSchemaManagerFgp.new(args).run
end
