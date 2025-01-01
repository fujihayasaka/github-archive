# typed: true
# frozen_string_literal: true

require "github/stream_processors/memex/message"
module GitHub
  module StreamProcessors
    module Memex
      class MilestoneUpdateMessage < MilestoneMessage
        def reason_to_ignore
          reason = super
          return reason if reason
          "no relevant change" unless title_changed? || state_changed? || due_on_changed?
        end

        private def title_changed?
          fetch(:previous_title) != fetch(:milestone, :title)
        end

        private def state_changed?
          fetch(:previous_state) != fetch(:milestone, :state)
        end

        private def due_on_changed?
          fetch(:previous_due_on) != fetch(:milestone, :due_on)
        end
      end
    end
  end
end
