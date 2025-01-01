# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module MigrationsVnextConfig
      def mvnd_client
        @mvnd_client ||= ::Mvnd::Client.new(
          mvnd_host,
          faraday_options: { timeout: 20 },
          hmac_key: mvnd_hmac_key
        )
      end

      def mvnd_host
        GitHub.environment.fetch("MVND_HOST", @mvnd_host)
      end

      def mvnd_hmac_key
        GitHub.environment["MVND_HMAC_KEY"]
      end
    end
  end

  extend Config::MigrationsVnextConfig
end
