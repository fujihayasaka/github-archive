# frozen_string_literal: true

module GitHub
  module Twirp
    class GlobalId
      class GetGlobalIdError < StandardError; end

      def initialize(client:)
        @client = client
      end

      # TODO: Consider moving metrics to a GitHub::Twirp::Client middleware the next time we add a client
      def get_github_next_global_id(global_relay_id)
        return global_relay_id if ::Dependabot.enterprise?

        MetricsClient.time("twirp.github.get_next_global_id") do
          get_next_global_id(global_relay_id)
        rescue Twirp::Error => e
          MetricsClient.increment("get_next_global_id.error")
          ::Dependabot::Logger.log_exception(e, { global_relay_id: global_relay_id })
          raise GetGlobalIdError, "unable to get next_global_id for the given global_relay_id: #{global_relay_id}"
        end
      end

      private

      def get_next_global_id(global_relay_id)
        resp = global_id_api.get_next_global_id(global_id: global_relay_id)

        raise Twirp::Error, "GitHub Error: '#{resp.error.msg}'" if resp.error

        resp.data.next_global_id
      end

      def global_id_api
        @global_id_api ||= MonolithTwirp::Actions::Core::V1::GlobalIdAPIClient.
                           new(@client.connection)
      end
    end
  end
end
