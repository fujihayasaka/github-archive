# typed: true
# frozen_string_literal: true

module Permissions
  module Enumerators
    class ManageAllApps < Permissions::Enumerator
      def actor_ids
        Permissions::Service.actor_ids_granted_permission(
          actor_type: Permissions::Granters::ManageAllApps::ACTOR_TYPE,
          subject_type: Permissions::Granters::ManageAllApps::SUBJECT_TYPE,
          subject_ids: [subject_id],
          action: Permissions::Granters::ManageAllApps::ACTION_TO_INT,
        )
      end
    end
  end
end
