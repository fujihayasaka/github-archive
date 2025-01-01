# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      class PullSharkProcessor < AchievementsBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :PULL_SHARK.freeze
        DEFAULT_GROUP_ID = "pull_shark_processor"
        EVENT_CLASSES = [Events::PullSharkEvent].freeze

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= EVENT_CLASSES.flat_map(&:matching_schema)

          self.metric_prefix = "achievements_processor.pull_shark"
          self.dead_letter_topic = "achievements.v0.PullShark.DeadLetter"
        end
      end
    end
  end
end
