# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      class QuickdrawProcessor < AchievementsBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :QUICKDRAW.freeze
        DEFAULT_GROUP_ID = "quickdraw_processor"
        EVENT_CLASSES = [Events::QuickdrawEvent].freeze

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= EVENT_CLASSES.flat_map(&:matching_schema)

          self.metric_prefix = "achievements_processor.quickdraw"
          self.dead_letter_topic = "achievements.v0.Quickdraw.DeadLetter"
        end
      end
    end
  end
end
