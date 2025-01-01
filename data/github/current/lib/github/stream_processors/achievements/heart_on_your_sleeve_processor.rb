# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      class HeartOnYourSleeveProcessor < AchievementsBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :HEART_ON_YOUR_SLEEVE.freeze
        DEFAULT_GROUP_ID = "heart_on_your_sleeve_processor"
        EVENT_CLASSES = [Events::HeartOnYourSleeveEvent].freeze

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= EVENT_CLASSES.flat_map(&:matching_schema)

          self.metric_prefix = "achievements_processor.heart_on_your_sleeve"
          self.dead_letter_topic = "achievements.v0.HeartOnYourSleeve.DeadLetter"
        end
      end
    end
  end
end
