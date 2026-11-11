# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      module Events
        class UserBehaviorEvent < UserMetadataEvent
          SKIP_REASON = "message does not involve a billing plan change"
          RESOURCES = %w[BillingProduct CouponRedemption].freeze
          RESOURCE_ACTIONS = %w(create delete).freeze

          def skip?
            !related_user_behavior?
          end

          def skip_reason
            SKIP_REASON
          end

          def users
            target_entity_owner_id = message.value.dig(:target_entity_owner, :id)
            with_read { User.where(id: target_entity_owner_id) }
          end

          private

          def resource_from_message
            message.value.dig(:resource, :value)
          end

          def resource_action_from_message
            message.value.dig(:resource_action, :value)
          end

          def related_user_behavior?
            resource = resource_from_message
            resource_action = resource_action_from_message

            RESOURCES.include?(resource) && RESOURCE_ACTIONS.include?(resource_action)
          end
        end
      end
    end
  end
end
