# typed: false
# frozen_string_literal: true

module Platform
  module Interfaces
    module MemberStatusable
      include Platform::Interfaces::Base
      description "Entities that have members who can set status messages."

      field :member_statuses, Connections.define(Objects::UserStatus), null: false,
        connection: true,
        description: "Get the status messages members of this entity have set that are " \
                     "either public or visible only to the organization." do
        argument :order_by, Inputs::UserStatusOrder, "Ordering options for user statuses returned from the connection.", required: false,
          default_value: { field: "updated_at", direction: "DESC" }
      end

      def member_statuses(order_by: nil)
        if @object.respond_to?(:member_or_can_view_members?)
          if @object.member_or_can_view_members?(@context[:viewer])
            include_private_org_members = context[:permission].can_list_private_org_members?(@object)
            ArrayWrapper.new(@object.member_statuses(
              order_by: order_by,
              viewer: @context[:viewer],
              include_private_org_members: include_private_org_members
            ))
          else
            ::UserStatus.none
          end
        elsif GitHub.enterprise? && @context[:viewer]&.site_admin?
          ArrayWrapper.new(@object.member_statuses(order_by: order_by, viewer: @context[:viewer]))
        else
          @object.async_visible_to?(@context[:viewer]).then do |is_team_visible|
            if is_team_visible
              ArrayWrapper.new(@object.member_statuses(order_by: order_by, viewer: @context[:viewer]))
            else
              ::UserStatus.none
            end
          end
        end
      end
    end
  end
end
