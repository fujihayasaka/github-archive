# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class OrganizationMember < Edges::User
      description "Represents a user within an organization."

      node_type Objects::User

      field :has_two_factor_enabled, Boolean, null: true,
        description: "Whether the organization member has two factor enabled or not. Returns null if information is not available to viewer."

      def has_two_factor_enabled
        org = object.parent
        org.async_adminable_by?(context[:viewer]).then do |adminable|
          next unless adminable
          next unless context[:permission].can_list_private_org_members?(org)

          object.node.async_two_factor_authentication_enabled?
        end
      end

      field :role, Enums::OrganizationMemberRole,
        description: "The role this user has in the organization.", null: true

      def role
        org = object.parent
        return unless org.member_or_can_view_members?(context[:viewer])
        return unless context[:permission].can_list_private_org_members?(org)

        user = object.node
        types = org.role_of(user).types

        if types.include?(:admin)
          "admin"
        elsif types.include?(:direct_member)
          "member"
        end
      end
    end
  end
end
