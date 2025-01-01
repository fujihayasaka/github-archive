# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module MemexLiveUpdates
      module Strategy
        class Result
          attr_reader :sockets_updated, :error_message

          def initialize(sockets_updated: 0, error_message: nil)
            @sockets_updated = sockets_updated
            @error_message = error_message
          end

          def success?
            error_message.nil?
          end

          def failure?
            !success?
          end
        end
      end
    end
  end
end
