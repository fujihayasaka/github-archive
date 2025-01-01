# typed: true
# frozen_string_literal: true

require "github/stream_processors/memex/message"
module GitHub
  module StreamProcessors
    module Memex
      class MilestoneMessage < Message
        def milestone_id
          fetch(:milestone, :id)
        end
      end
    end
  end
end
