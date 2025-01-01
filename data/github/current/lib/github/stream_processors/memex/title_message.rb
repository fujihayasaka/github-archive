# typed: true
# frozen_string_literal: true

require "github/stream_processors/memex/message"

module GitHub
  module StreamProcessors
    module Memex
      class TitleMessage < Message
        def state_change?
          !(@message.schema =~ ISSUE_UPDATE_TOPIC)
        end
      end
    end
  end
end
