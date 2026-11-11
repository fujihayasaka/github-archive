# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module Events
        autoload :AchievementEvent, "github/stream_processors/achievements/events/achievement_event"

        autoload :GalaxyBrainEvent, "github/stream_processors/achievements/events/galaxy_brain_event"
        autoload :HeartOnYourSleeveEvent, "github/stream_processors/achievements/events/heart_on_your_sleeve_event"
        autoload :HeartbreakerEvent, "github/stream_processors/achievements/events/heartbreaker_event"
        autoload :OpenSourcererEvent, "github/stream_processors/achievements/events/open_sourcerer_event"
        autoload :PairExtraordinaireEvent, "github/stream_processors/achievements/events/pair_extraordinaire_event"
        autoload :PublicSponsorEvent, "github/stream_processors/achievements/events/public_sponsor_event"
        autoload :PullSharkEvent, "github/stream_processors/achievements/events/pull_shark_event"
        autoload :QuickdrawEvent, "github/stream_processors/achievements/events/quickdraw_event"
        autoload :StarstruckEvent, "github/stream_processors/achievements/events/starstruck_event"
        autoload :UnknownEvent, "github/stream_processors/achievements/events/unknown_event"
        autoload :YoloEvent, "github/stream_processors/achievements/events/yolo_event"
      end
    end
  end
end
