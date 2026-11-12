# frozen_string_literal: true

module AdvisoryDB
  module Config
    module Slack
      def slack_enabled?
        slack_api_token.present?
      end

      def slack_api_token
        ENV.fetch("SLACK_API_TOKEN", nil)
      end

      def slack_channel
        ENV.fetch("SLACK_CHANNEL", nil)
      end

      def curation_slack_channel
        ENV.fetch("CURATION_SLACK_CHANNEL", nil)
      end

      def slack
        return @slack if defined? @slack
        return unless slack_enabled?

        @slack = ::Slack::Web::Client.new(token: slack_api_token)
      end
    end

    include Slack
  end
end
