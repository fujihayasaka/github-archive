# typed: strict
# frozen_string_literal: true

# Roles::Types::Role serializes roles for role management UIs (creation/editing)
# using the selected_permissions format for the custom-roles React app.
#
# For role assignments UI, see RoleAssignments::Types::Role which uses the
# fgpMetadata format.

module Roles
  module Types
    class Role < T::Struct
      const :id, Integer
      const :name, String
      const :description, T.nilable(String)
      const :selected_permissions, T.nilable(T::Hash[Symbol, T::Array[T::Hash[Symbol, T.untyped]]])
      const :selected_base_role, T.nilable(T::Hash[Symbol, String])
      const :assignee_count, T::Hash[Symbol, Integer]

      # Create a Role from a model
      sig do
        params(role: ::Role).returns(Role)
      end
      def self.from_model(role)
        role_data = {
          id: role.id,
          name: role.display_name,
          description: role.description,
          selected_permissions: {
            Organization: serialize_permissions(OrgFgpMetadata.fgps_for_role(role)),
            Repository: serialize_permissions(RepoFgpMetadata.fgps_for_role(role)),
            Enterprise: serialize_permissions(EnterpriseFgpMetadata.fgps_for_role(role)),
          },
          assignee_count: {
            users: role.user_count,
            teams: role.team_count,
          }
        }

        base_role = role.base_role&.display_name&.downcase
        role_data[:selected_base_role] = { Repository: base_role } if base_role.present?
        if role.is_a?(RepositoryRole) && role.custom?
          role_data[:assignee_count].merge!({
            org_members: role.org_member_count,
            collaborators: role.collaborator_count,
            invitations: RepositoryInvitation.where(role_id: role.id).count
          })
        end

        Role.new(role_data)
      end

      sig { params(options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def as_json(options = {})
        hash = {
          id:,
          name:,
          description:,
          selectedPermissions: selected_permissions,
          selectedBaseRole: selected_base_role,
          assigneeCount: assignee_count,
        }
        hash
      end

      # Serialize FGPs from grouped hash to flat array format
      #
      # The metadata classes (OrgFgpMetadata, etc.) preload the category titles and group
      # FGPs by category, returning: { "Category Title" => [<FGP>, <FGP>], ... }
      #
      # This method flattens that structure into an array where each permission includes
      # its category title, suitable for the selected_permissions format.
      sig do
        params(
          grouped_fgps: T::Hash[String, T::Array[Permissions::FineGrainedPermissionIm]]
        ).returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def self.serialize_permissions(grouped_fgps)
        grouped_fgps.flat_map do |category_title, fgps|
          fgps.map do |fgp|
            {
              label: fgp.action.to_sym,
              description: fgp.description,
              category: category_title,
            }
          end
        end
      end
    end
  end
end
