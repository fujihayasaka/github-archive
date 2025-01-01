# typed: true
# frozen_string_literal: true

module Permissions
  module Enumerators
    class ManageApp < Permissions::Enumerator
      def actor_ids
        Permissions::Service.actor_ids_granted_permission(
          actor_type: Permissions::Granters::ManageApp::ACTOR_TYPE,
          subject_type: Permissions::Granters::ManageApp::SUBJECT_TYPE,
          subject_ids: [subject_id],
          action: Permissions::Granters::ManageApp::ACTION_TO_INT,
        )
      end

      def subject_ids
        Permissions::Service.subject_ids_granted_permission(
          actor_ids: [actor_id],
          actor_type: Permissions::Granters::ManageApp::ACTOR_TYPE,
          subject_type: Permissions::Granters::ManageApp::SUBJECT_TYPE,
          action: Permissions::Granters::ManageApp::ACTION_TO_INT,
        )
      end
    end
  end
end
