# typed: true
# frozen_string_literal: true

module ProgrammaticAccessToken
  class Destroyer
    SUCCESS_RESULTS = [
      :RESULT_ALREADY_REVOKED,
      :RESULT_NOT_FOUND,
      :RESULT_SUCCESS
    ]

    VALID_DESTROY_REASONS = {
      web_user: "deleted on #{GitHub.host_name}",
      regeneration: "deleted by regeneration on #{GitHub.host_name}",
      site_admin: "deleted by GitHub staff",
    }

    STATS_KEY = "programmatic_access_token.destroyer"

    def self.perform(actor_id, access_id, opts = {})
      new(actor_id, access_id, opts).perform
    end

    def initialize(actor_id, access_id, opts)
      @actor_id = actor_id
      @access_id = access_id
      @opts = opts
    end

    def perform
      get_credentials_response = get_credentials
      return Result.failed(get_credentials_response.error) unless get_credentials_response.success?

      credential_ids = get_credentials_response.value.map(&:id)

      return Result.success if credential_ids.empty?

      revoke_credentials_response = credential_manager.revoke_credentials_by_id(
        destroy_reason,
        ProgrammaticAccessToken::Finder::TOKEN_TYPE,
        credential_ids
      )

      if failure = revoke_credentials_response.responses.find { |response| SUCCESS_RESULTS.exclude?(response.result) }
        raise Result::Error, failure.message
      end

      GitHub.dogstats.increment(STATS_KEY, tags: ["result:success"])
      Result.success
    rescue ::Authnd::Proto::Error, Faraday::Error, Result::Error => err
      GitHub.dogstats.increment(STATS_KEY, tags: ["result:failure"])
      Failbot.report!(err)
      Result.failed(err.message)
    end

    private

    def credential_manager
      ::GitHub::Authnd.credential_manager
    end

    def get_credentials
      ProgrammaticAccessToken::Finder
        .perform(@actor_id, @access_id, @opts)
    end

    def destroy_reason
      VALID_DESTROY_REASONS[@opts[:reason]]
    end
  end
end
