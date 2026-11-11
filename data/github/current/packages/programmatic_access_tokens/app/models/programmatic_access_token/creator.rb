# typed: true
# frozen_string_literal: true

module ProgrammaticAccessToken
  class Creator
    ACTOR_TYPE = "User"
    STATS_KEY = "programmatic_access_token.creator"

    def self.perform(actor_id, access_id, opts = {})
      new(actor_id, access_id, opts).perform
    end

    def initialize(actor_id, access_id, opts = {})
      @actor_id = actor_id
      @access_id = access_id
      @expires_at = opts[:expires_at]
    end

    def perform
      issue_token_response = credential_manager.issue_token(
        ProgrammaticAccessToken::Finder::TOKEN_TYPE,
        {
          "actor.id" => @actor_id,
          "actor.type" => ACTOR_TYPE,
          "access.id" => @access_id,
        },
        expires_at: @expires_at
      )

      unless issue_token_response.success?
        raise Result::Error, issue_token_response.error
      end

      GitHub.dogstats.increment(STATS_KEY, tags: ["result:success"])
      Result.success(issue_token_response.token)
    rescue ::Authnd::Proto::Error, Faraday::Error, Result::Error => err
      GitHub.dogstats.increment(STATS_KEY, tags: ["result:failure"])
      Failbot.report!(err)
      Result.failed(err.message)
    end

    private

    def credential_manager
      ::GitHub::Authnd.credential_manager
    end
  end
end
