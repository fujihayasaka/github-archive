# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      class StarstruckProcessor < AchievementsBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :STARSTRUCK.freeze
        DEFAULT_GROUP_ID = "starstruck_processor"
        EVENT_CLASSES = [Events::StarstruckEvent].freeze

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= EVENT_CLASSES.flat_map(&:matching_schema)

          self.metric_prefix = "achievements_processor.starstruck"
          self.dead_letter_topic = "achievements.v0.Starstruck.DeadLetter"
        end
      end
    end
  end
end
