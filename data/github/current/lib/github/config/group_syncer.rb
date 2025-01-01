# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module GroupSyncer
      # The URI the GroupSyncer service.
      #
      # e.g. "https://group-syncer.service.cp1-iad.github.net/twirp"
      attr_accessor :group_syncer_service_uri

      # The timeout Float in sceonds for requests to the GroupSyncer service.
      #
      # e.g. `2.0` seconds.
      attr_accessor :group_syncer_service_timeout

      # The secret key String for generating HMAC signatures to authenticate
      # requests to the GroupSyncer service.
      attr_accessor :group_syncer_service_hmac_secret_key

      # The secret key String for generating HMAC signatures to authenticate
      # requests to the GroupSyncer service, this is the updated / rotated key
      attr_accessor :group_syncer_service_hmac_secret_primary_key

      # The ID of the first class GitHub app we are using.
      attr_accessor :group_syncer_github_app_id
    end

    # Is the Team Synchronization feature available?
    #
    # This feature is only available in GHEC.
    #
    # Returns Boolean.
    def team_synchronization_available?
      !::GitHub.enterprise? && !::TestEnv.test_with_all_emus?
    end
  end

  extend Config::GroupSyncer
end
