# typed: strict
# frozen_string_literal: true

module RoleAssignments
  module Types

    class Role < T::Struct

      class FgpType < T::Enum
        enums do
          Enterprise = new(:enterprise)
          Organization = new(:organization)
          Repository = new(:repository)
        end
      end

      const :id, Integer
      const :name, String
      const :description, T.nilable(String)
      const :octicon, String
      const :delegate_role_id, T.nilable(Integer)
      const :is_delegate, T.nilable(T::Boolean)
      const :enterpriseOwner, T.nilable(T::Hash[Symbol, String])
      const :fgpMetadata, T.nilable(T::Hash[Symbol, T.untyped])

      # Create a Role from a model, optionally including delegate role and FGP metadata
      # `with_fgps` determines if FGP metadata should be included
      # `fgp_types` specifies which FGP types to include in the metadata. By default, it includes all types.
      sig do
        params(
          role: ::Role,
          delegate_role_id: T.nilable(Integer),
          is_delegate: T::Boolean,
          with_fgps: T::Boolean,
          fgp_types: T::Array[FgpType]
        ).returns(Role)
      end
      def self.from_model(
        role,
        delegate_role_id: nil,
        is_delegate: false,
        with_fgps: false,
        fgp_types: [FgpType::Enterprise, FgpType::Organization, FgpType::Repository]
      )
        role_data = {
          id: role.id,
          name: role.display_name,
          description: role.description,
          octicon: role.octicon,
          delegate_role_id:,
          is_delegate: is_delegate ? true : nil
        }

        return Role.new(role_data) unless with_fgps

        case role
        when OrganizationRole
          role_data.merge!(organization_role_attributes(role))
        when EnterpriseRole
          role_data.merge!(enterprise_role_attributes(role, fgp_types))
        end

        Role.new(role_data)
      end

      sig { params(roles: T::Array[::OrganizationRole], with_fgps: T::Boolean).returns(T::Array[Role]) }
      def self.from_org_roles(roles, with_fgps: false)
        GitHub::PrefillAssociations.prefill_associations(roles, [:permissions, :base_role]) if with_fgps

        roles.map do |role|
          from_model(role, with_fgps:)
        end
      end

      # Create roles from a collection of enterprise roles
      # Optionally including delegate roles (e.g. include OSM with ESM, to check for role assignments) and FGP metadata
      sig { params(roles: T::Array[::EnterpriseRole], include_delegate: T::Boolean, with_fgps: T::Boolean).returns(T::Array[Role]) }
      def self.from_enterprise_roles(roles, include_delegate: false, with_fgps: false)
        # Prefill delegate even if include_delegate is false because it will be used for FGP metadata
        GitHub::PrefillAssociations.prefill_batch_method(roles, :delegate_organization_role) if include_delegate || with_fgps

        if with_fgps
          all_roles_for_permissions = roles.dup
          delegate_roles = roles.filter_map(&:delegate_organization_role)
          all_roles_for_permissions.concat(delegate_roles)
          GitHub::PrefillAssociations.prefill_associations(all_roles_for_permissions, [:permissions, :base_role])
        end

        return roles.map { |role| from_model(role, with_fgps:) } unless include_delegate


        all_roles = roles.flat_map do |role|
          role_list = [from_model(role, delegate_role_id: role.delegate_organization_role&.id, with_fgps:)]

          # We don't display the FGPs for the delegate role, so we do not need to include them even if with_fgps is true
          if role.delegate_organization_role.present?
            role_list << from_model(T.must(role.delegate_organization_role), is_delegate: true, with_fgps: false)
          end

          role_list
        end
      end

      # Define serialization for React payload
      sig { params(options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def as_json(options = {})
        json = {
          id:,
          name:,
          description:,
          octicon:,
        }

        json[:enterpriseOwner] = enterpriseOwner if enterpriseOwner
        json[:fgpMetadata] = fgpMetadata if fgpMetadata
        json
      end

      sig { params(role: OrganizationRole).returns(T::Hash[Symbol, T.untyped]) }
      def self.organization_role_attributes(role)
        enterprise_owner = if role.enterprise_owned?
          {
            name: role.owner.name,
            slug: role.owner.slug,
          }
        end

        attributes = {
          fgpMetadata: {
            Organization: OrgFgpMetadata.for_role(role),
            Repository: RepoFgpMetadata.for_role(role),
          },
          enterpriseOwner: enterprise_owner,
        }

        base_role = role.base_role&.display_name
        attributes[:fgpMetadata].merge!(
          baseRepositoryRole: base_role,
        ) if base_role.present?

        attributes
      end

      sig { params(role: EnterpriseRole, fgp_types: T::Array[FgpType]).returns(T::Hash[Symbol, T.untyped]) }
      def self.enterprise_role_attributes(role, fgp_types)
        attributes = { fgpMetadata: {} }

        attributes[:fgpMetadata].merge!(
            Enterprise: EnterpriseFgpMetadata.for_role(role)
        ) if fgp_types.include?(FgpType::Enterprise)

        delegate_role = role.delegate_organization_role
        return attributes unless delegate_role

        attributes[:fgpMetadata].merge!(
          Organization: OrgFgpMetadata.for_role(delegate_role)
        ) if fgp_types.include?(FgpType::Organization)

        attributes[:fgpMetadata].merge!(
          Repository: RepoFgpMetadata.for_role(delegate_role)
        ) if fgp_types.include?(FgpType::Repository)

        base_role = delegate_role.base_role&.display_name
        attributes[:fgpMetadata].merge!(
          baseRepositoryRole: base_role,
        ) if base_role.present?

        attributes
      end
    end
  end
end
