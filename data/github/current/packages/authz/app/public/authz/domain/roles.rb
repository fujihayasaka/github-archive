# typed: strict
# frozen_string_literal: true

module Authz
  class Domain
    class Roles < GH::Domain::Base
      class Source < T::Enum
        enums do
          Custom = new(:custom)
          Preset = new(:preset)
        end
      end

      # Public: Find all custom organization roles for a given fine-grained
      # permission.
      #
      # org    - The Organization whose custom roles searching against.
      # fgp    - The fine-grained permission.
      # filter - The Source to filter roles by (Source::Custom or Source::Preset).
      #
      # Examples
      #
      #     domain.roles.visible_custom_org_role_with_fgp(
      #       Organization.find(1),
      #       :view_org_integrations
      #     )
      #     # => [37, 42, 70]
      #
      # Returns an Array of Role IDs.
      sig { params(org: Organization, fgp: Symbol, filter: T.nilable(Source)).returns(T::Array[Integer]) }
      def visible_org_role_ids_with_fgp(org, fgp, filter: nil) # rubocop:disable Metrics/MethodLength
        org_role_ids = OrganizationRole.visible_roles(org).map(&:id)

        scope = Role.select(:id).joins(:permissions)

        case filter
        when Source::Custom
          scope = scope.custom
        when Source::Preset
          scope = scope.presets
        when nil
          # No additional filtering needed
        else
          T.absurd(filter)
        end

        scope.where(permissions: { role_id: org_role_ids, action: fgp }).pluck(:id)
      end

      # Public: Find all roles for the given list of IDs.
      # permission.
      #
      # role_ids - An Array of Integer role IDs.
      #
      # Examples
      #
      #     domain.roles.with_ids([1, 2])
      #     # => [#<Role id: 1, ...>]
      #
      # Returns an Array of Role objects.
      sig { params(role_ids: T::Array[Integer]).returns(T::Array[Role]) }
      def with_ids(role_ids)
        Role.where(id: role_ids).to_a
      end
    end
  end
end
