# typed: strict
# frozen_string_literal: true

module Search
  module Responses
    module SharedMemexProjectItemApiResponseHelpers
      extend T::Helpers

      sig { params(exception: T.nilable(ElastomerClient::Client::Error)).returns(T.nilable(String)) }
      def sanitize_exception(exception)
        return unless exception
        # For now, we only communicate retryable errors to the client so that we can retry automatically or notify the user.
        # Other kinds of errors are handled elsewhere. See the github/elastomer-client repo for more information about
        # which errors are retryable and which are not:
        #
        # https://github.com/github/elastomer-client/blob/main/lib/elastomer_client/client/errors.rb
        return unless exception.retry?
        "Service is unavailable. Please try again later. (Request id: #{GitHub.context[:request_id] || 'unknown' })"
      end
    end
  end
end
