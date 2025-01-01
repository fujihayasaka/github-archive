# typed: strict
# frozen_string_literal: true

module GitHubUI
  class Redis
    sig { returns(::Redis) }
    def self.client
      @github_ui_deploys_redis ||= T.let(::Redis.new(GitHub.read_redis_config("config/redis_github_ui_deploys.yml", read_timeout: 0.2, connect_timeout: 0.2)), T.nilable(::Redis))
    end
  end
end
