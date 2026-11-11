# frozen_string_literal: true

require "proto/jobs/v1/jobs_api_pb"
require "proto/jobs/v1/jobs_api_twirp"

module Sweagentd
  module Proto
    class Client
      # Initialize with a Faraday::Connection.
      def initialize(connection)
        @connection = connection
      end

      def service
        @service ||= Sweagentd::JobsAPI::V1::JobsAPIClient.new(@connection)
      end
    end
  end
end
