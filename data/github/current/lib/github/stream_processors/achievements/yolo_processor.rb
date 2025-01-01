# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      class YoloProcessor < AchievementsBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :yolo.freeze
        DEFAULT_GROUP_ID = "yolo_processor"
        EVENT_CLASSES = [Events::YoloEvent].freeze

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= EVENT_CLASSES.flat_map(&:matching_schema)

          self.metric_prefix = "achievements_processor.yolo"
          self.dead_letter_topic = "achievements.v0.Yolo.DeadLetter"
        end
      end
    end
  end
end
