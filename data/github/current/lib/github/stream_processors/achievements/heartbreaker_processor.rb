# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      class HeartbreakerProcessor < AchievementsBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :HEARTBREAKER.freeze
        DEFAULT_GROUP_ID = "heartbreaker_processor"
        THRESHOLD = 100
        EVENT_CLASSES = [Events::HeartbreakerEvent].freeze

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= EVENT_CLASSES.flat_map(&:matching_schema)

          self.metric_prefix = "achievements_processor.heartbreaker"
          self.dead_letter_topic = "achievements.v0.Heartbreaker.DeadLetter"
        end
      end
    end
  end
end
