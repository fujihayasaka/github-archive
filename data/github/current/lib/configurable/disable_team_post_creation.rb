# typed: false
# frozen_string_literal: true

module Configurable
  module DisableTeamPostCreation
    KEY = "team_post_creation.enable".freeze

    # Determine if team does not allow post creation
    def team_post_creation_disabled?
      !team_post_creation_enabled?
    end

    # Determine if team allows general post creation
    def team_post_creation_enabled?
      config.get(KEY).nil? || config.enabled?(KEY)
    end

    # Enable the ability to create posts on a team
    def enable_team_post_creation(actor:)
      config.enable!(KEY, actor)
    end

    # Disable the ability to create posts on a team
    def disable_team_post_creation(actor:)
      config.disable!(KEY, actor)
    end
  end
end
