
# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      module Events
        class RecalculationEvent < UserMetadataEvent
          SKIP_REASON = "unrelated recalculation event"

          def recalculation?
            true
          end

          def skip?
            unrelated_recalc_requested?
          end

          def skip_reason
            SKIP_REASON
          end

          def users
            target_user_id = message.value.dig(:target_user, :id)
            with_read { User.where(id: target_user_id) }
          end

          private

          def unrelated_recalc_requested?
            target_stream_processor = message.value.dig(:target_stream_processor)
            target_stream_processor != processor.name && target_stream_processor != :ALL
          end
        end
      end
    end
  end
end
