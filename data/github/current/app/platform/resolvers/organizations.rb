# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Organizations < Resolvers::Base
      type Connections.define(Objects::Organization), null: false

      argument :logins, [String], "A list of organization logins to filter by.", required: false, visibility: :internal

      argument :database_ids, [Integer], "A list of organization database IDs to filter by.", required: false, visibility: :internal

      argument :order_by,
        Inputs::OrganizationOrder,
        "Ordering options for the User's organizations.",
        required: false,
        default_value: nil

      def resolve(logins: nil, database_ids: nil, order_by: nil)
        conditions = []

        if database_ids.present?
          conditions << Organization.where(id: database_ids)
        end

        if logins.present?
          conditions << Organization.where(login: logins)
        end

        orgs = case object
        when UserHovercard::Contexts::Organizations
          object.highlighted
        when User
          if object.private_profile_for?(context[:viewer])
            return Organization.none
          elsif context[:permission].can_list_private_org_memberships?(object)
            viewable_org_ids = if context[:viewer].can_have_granular_permissions?
              target = context[:viewer].ability_delegate.target

              can_list_private_org_memberships = \
                target.organization? && context[:permission].can_list_private_org_members?(target)

              can_list_private_org_memberships ? [target.id] : []
            elsif ProgrammaticActor::OrganizationFilter.applicable?(context[:viewer])
              ProgrammaticActor::OrganizationFilter.perform(
                actor: context[:viewer], resource: "members",
                organization_ids: context[:viewer].organization_ids
              )
            else
              context[:viewer].organization_ids
            end

            viewable_org_ids |= object.public_organizations.pluck(:id)
            object.organizations.where(id: viewable_org_ids)
          else
            object.public_organizations
          end
        when Platform::Objects::ExternalIdentity::AdminableMember
          object.organizations_visible_to(context[:viewer])
        else
          ::Organization
        end

        orgs = orgs.and(conditions.reduce { |a, b| a.or(b) }) if conditions.present?

        if order_by && order_by[:field].present? && order_by[:direction].present?
          orgs = orgs.order(order_by[:field] => order_by[:direction])
        end

        if context[:unauthorized_organization_ids].present?
          # organizations are a part of the users table, so we need to filter ids on the users table
          orgs = orgs.where("users.id NOT IN (?)", context[:unauthorized_organization_ids])
        end

        orgs.filter_spam_for(context[:viewer])
      end
    end
  end
end
