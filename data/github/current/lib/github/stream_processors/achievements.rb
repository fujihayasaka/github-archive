# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      autoload :AchievementsBaseProcessor, "github/stream_processors/achievements/achievements_base_processor"

      autoload :GalaxyBrainProcessor, "github/stream_processors/achievements/galaxy_brain_processor"
      autoload :HeartOnYourSleeveProcessor, "github/stream_processors/achievements/heart_on_your_sleeve_processor"
      autoload :HeartbreakerProcessor, "github/stream_processors/achievements/heartbreaker_processor"
      autoload :OpenSourcererProcessor, "github/stream_processors/achievements/open_sourcerer_processor"
      autoload :PairExtraordinaireProcessor, "github/stream_processors/achievements/pair_extraordinaire_processor"
      autoload :PublicSponsorProcessor, "github/stream_processors/achievements/public_sponsor_processor"
      autoload :PullSharkProcessor, "github/stream_processors/achievements/pull_shark_processor"
      autoload :QuickdrawProcessor, "github/stream_processors/achievements/quickdraw_processor"
      autoload :StarstruckProcessor, "github/stream_processors/achievements/starstruck_processor"
      autoload :YoloProcessor, "github/stream_processors/achievements/yolo_processor"

      autoload :Events, "github/stream_processors/achievements/events"

      autoload :ProcessingMethods, "github/stream_processors/achievements/processing_methods"
    end
  end
end
