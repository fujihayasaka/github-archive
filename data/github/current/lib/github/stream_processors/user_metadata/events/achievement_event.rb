# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      module Events
        class AchievementEvent < UserMetadataEvent
          SKIP_REASON_UNRECOGNIZED_VISIBILITY = "Unrecognized visibility"
          SKIP_REASON_MISSING_USER = "Achieving user not found"

          def skip?
            skip_reason.present?
          end

          def skip_reason
            if !public? && !private?
              SKIP_REASON_UNRECOGNIZED_VISIBILITY
            elsif users.empty?
              SKIP_REASON_MISSING_USER
            end
          end

          def users
            @users ||= with_read { User.where(id: user_id) }
          end

          def public?
            visibility == :PUBLIC
          end

          def private?
            visibility == :PRIVATE
          end

          private

          def user_id
            message.value.dig(:user, :id)
          end

          def visibility
            message.value[:visibility]
          end
        end
      end
    end
  end
end
