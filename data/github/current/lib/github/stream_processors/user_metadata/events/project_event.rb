# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      module Events
        class ProjectEvent < UserMetadataEvent
          SKIP_REASON = "project not created, deleted, opened, or closed"
          VALID_ACTIONS = [:CREATE, :CLOSE, :OPEN, :UPDATE, :DELETE].freeze

          def skip?
            !valid_action?
          end

          def skip_reason
            SKIP_REASON
          end

          alias :users :actors

          private

          def valid_action?
            action = message.value[:action]
            VALID_ACTIONS.include?(action&.to_sym)
          end
        end
      end
    end
  end
end
