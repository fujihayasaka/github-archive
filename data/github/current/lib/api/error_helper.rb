# typed: true
# frozen_string_literal: true
module Api
  module ErrorHelper
    RATE_LIMIT_REQUEST_ID_MESSAGE = " If you reach out to GitHub Support for help, please include the request ID %s.".freeze

    RATE_LIMIT_REQUEST_ID_WITH_TIMESTAMP_MESSAGE = " If you reach out to GitHub Support for help, please include the request ID %s and timestamp %s.".freeze

    def self.rate_limit_message_for_request_id(request_id, timestamp = Time.now.utc)
      return "" unless request_id.present?

      RATE_LIMIT_REQUEST_ID_WITH_TIMESTAMP_MESSAGE % [request_id, timestamp]
    end
  end
end
