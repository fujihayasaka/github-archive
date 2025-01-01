# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module Events
        class UnknownEvent < AchievementEvent
          SKIP_REASON = "unknown message schema"

          def skip?
            true
          end

          def skip_reason
            SKIP_REASON
          end
        end
      end
    end
  end
end
