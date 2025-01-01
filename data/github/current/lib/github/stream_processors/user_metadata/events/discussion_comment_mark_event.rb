# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      module Events
        class DiscussionCommentMarkEvent < UserMetadataEvent
          def skip?
            false
          end

          def users
            author_id = message.value.dig(:author, :id)
            with_read { User.where(id: author_id) }
          end
        end
      end
    end
  end
end
