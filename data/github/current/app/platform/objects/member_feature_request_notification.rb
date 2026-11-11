# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MemberFeatureRequestNotification < Platform::Objects::Base
      model_name "MemberFeatureRequest::Notification"

      description "Represents a member feature request notification"

      implements_node templates: [
        [:rafn, :user_id, :id]
      ], as: "RAFN", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |member_feature_request_notification|
        {
          prefix: :rafn,
          user_id: member_feature_request_notification.user_id,
          id: member_feature_request_notification.id,
        }
      end

      def self.async_api_can_access?(permission, object)
        object.async_readable_by?(permission.viewer)
      end

      def self.async_viewer_can_see?(permission, object)
        object.async_readable_by?(permission.viewer)
      end

      field :title, String, "Represents member feature request notification title", null: false
      field :body, String, "Represents member feature request body containing entity name and the number of feature requests", null: false

      updated_at_field
    end
  end
end
