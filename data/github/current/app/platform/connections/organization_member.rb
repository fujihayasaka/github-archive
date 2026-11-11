# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class OrganizationMember < Connections::Base
      description "A list of users who belong to the organization."

      TOTAL_COUNT_BATCH_SIZE = 10_000

      total_count_field

      def total_count
        viewer = context[:viewer]

        if context[:permission].can_list_private_org_members?(@object.parent)
          user_ids = @object.parent.visible_user_ids_for(viewer, limit: nil)
        else
          user_ids = @object.parent.public_member_ids
        end
        return 0 if user_ids.empty?

        return user_ids.size unless GitHub.spamminess_check_enabled?
        return user_ids.size if viewer && viewer.site_admin?

        user_ids.each_slice(TOTAL_COUNT_BATCH_SIZE).inject(0) do |acc, ids|
          acc += ::User.where(id: ids).filter_spam_for(viewer).count
        end
      end

    end
  end
end
