# frozen_string_literal: true

module AdvisoryDB
  module Config
    module Redis
      def redis_password
        ENV.fetch("REDIS_PASSWORD", nil)
      end

      def redis_url
        ENV.fetch("REDIS_URL", nil)
      end

      def redis_username
        ENV.fetch("REDIS_USERNAME", nil)
      end

      def redis
        @redis ||= ::Redis.new(url: redis_url, username: redis_username, password: redis_password)
      end
    end

    include Redis
  end
end
