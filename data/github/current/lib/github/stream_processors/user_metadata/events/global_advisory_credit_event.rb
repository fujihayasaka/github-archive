# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      module Events
        class GlobalAdvisoryCreditEvent < UserMetadataEvent
          def skip?
            false
          end

          def users
            recipient_id = message.value.dig(:advisory_credit_recipient, :id)
            with_read { User.where(id: recipient_id) }
          end
        end
      end
    end
  end
end
