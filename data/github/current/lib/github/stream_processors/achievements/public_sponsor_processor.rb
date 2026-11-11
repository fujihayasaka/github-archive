# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      class PublicSponsorProcessor < AchievementsBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :PUBLIC_SPONSOR.freeze
        DEFAULT_GROUP_ID = "public_sponsor_processor"
        EVENT_CLASSES = [Events::PublicSponsorEvent].freeze

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= EVENT_CLASSES.flat_map(&:matching_schema)

          self.metric_prefix = "achievements_processor.public_sponsor"
          self.dead_letter_topic = "achievements.v0.PublicSponsor.DeadLetter"
        end
      end
    end
  end
end
