# typed: true
# frozen_string_literal: true

module Stafftools
  class UserMetadataUpdater
    ATTRIBUTE_STREAM_PROCESSOR_MAPPING = {
      "all"                                          => :ALL,
      "achievements"                                 => :ACHIEVEMENTS,
      "discussion_answered_count"                    => :DISCUSSION_ANSWERS,
      "discussion_answered_public_and_private_count" => :DISCUSSION_ANSWERS,
      "followers_count"                              => :FOLLOWS,
      "following_count"                              => :FOLLOWS,
      "global_advisory_credit_count"                 => :GLOBAL_ADVISORY_CREDITS,
      "packages_count"                               => :PACKAGES,
      "packages_public_and_private_count"            => :PACKAGES,
      "projects_count"                               => :PROJECTS,
      "projects_public_and_private_count"            => :PROJECTS,
      "repository_count"                             => :REPOSITORIES,
      "repository_public_and_private_count"          => :REPOSITORIES,
      "stars_count"                                  => :STARS,
      "sponsoring_count"                             => :SPONSORS,
      "sponsoring_public_and_private_count"          => :SPONSORS,
      "sponsors_count"                               => :SPONSORS,
      "sponsors_public_and_private_count"            => :SPONSORS,
      "inactive_sponsors_public_and_private_count"   => :SPONSORS,
      "inactive_sponsors_count"                      => :SPONSORS,
      "inactive_sponsoring_public_and_private"       => :SPONSORS,
      "inactive_sponsoring_count"                    => :SPONSORS,
    }.freeze

    def initialize(user:)
      @user = user
    end

    def trigger_recalculation!(attribute_to_recalculate:)
      GlobalInstrumenter.instrument(
        "user_metadata.recalculation.trigger",
        {
          actor_id: user.id,
          target_user_id: user.id,
          target_stream_processor: ATTRIBUTE_STREAM_PROCESSOR_MAPPING[attribute_to_recalculate],
        },
      )
    end

    def toggle!(attribute_to_toggle:)
      return false unless metadata

      metadata.update(attribute_to_toggle => !metadata.attributes[attribute_to_toggle])
    end

    private

    attr_reader :user

    def metadata
      user.user_metadata
    end
  end
end
