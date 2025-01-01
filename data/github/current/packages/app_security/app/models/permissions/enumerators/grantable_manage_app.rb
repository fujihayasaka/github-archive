# typed: true
# frozen_string_literal: true

module Permissions
  module Enumerators
    class GrantableManageApp < Permissions::Enumerator
      def actor_ids
        return [] unless context[:owner_id]
        all_members = Enumerators::BelongToOrganization.new(subject_id: context[:owner_id]).actor_ids

        all_members - can_already_manage_app
      end

      private

      def can_already_manage_app
        already_granted_permission = Enumerators::ManageApp.new(subject_id: subject_id).actor_ids
        owners = Enumerators::OwnOrganization.new(subject_id: context[:owner_id]).actor_ids
        all_apps_managers = Enumerators::ManageAllApps.new(subject_id: context[:owner_id]).actor_ids

        (already_granted_permission + owners + all_apps_managers).uniq
      end
    end
  end
end
