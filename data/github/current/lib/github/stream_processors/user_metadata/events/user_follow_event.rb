# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      module Events
        class UserFollowEvent < UserMetadataEvent
          def skip?
            false
          end

          def users
            with_read { User.where(type: "User", id: [follower_id, followee_id]) }
          end

          def user_is_follower?(user)
            user.id == follower_id
          end

          def user_is_followee?(user)
            user.id == followee_id
          end

          private

          def follower_id
            message.value.dig(:actor, :id)
          end

          def followee_id
            message.value.dig(:followee, :id)
          end
        end
      end
    end
  end
end
