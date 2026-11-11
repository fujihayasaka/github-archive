# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      class GalaxyBrainProcessor < AchievementsBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :GALAXY_BRAIN.freeze
        DEFAULT_GROUP_ID = "galaxy_brain_processor"
        EVENT_CLASSES = [Events::GalaxyBrainEvent].freeze

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= EVENT_CLASSES.flat_map(&:matching_schema)

          self.metric_prefix = "achievements_processor.galaxy_brain"
          self.dead_letter_topic = "achievements.v0.GalaxyBrain.DeadLetter"
        end
      end
    end
  end
end
