# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      class OpenSourcererProcessor < AchievementsBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :OPEN_SOURCERER.freeze
        DEFAULT_GROUP_ID = "open_sourcerer_processor"
        EVENT_CLASSES = [Events::OpenSourcererEvent].freeze

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= EVENT_CLASSES.flat_map(&:matching_schema)

          self.metric_prefix = "achievements_processor.open_sourcerer"
          self.dead_letter_topic = "achievements.v0.OpenSourcerer.DeadLetter"
        end
      end
    end
  end
end
