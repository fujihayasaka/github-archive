# typed: true
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      class Error < StandardError
        attr_reader :original_error

        def initialize(message, original_error: nil)
          super(message)
          @original_error = original_error
          set_backtrace caller
        end

        def http_5xx?
          (500..599).cover?(http_status)
        end

        def http_409?
          http_status == 409
        end

        def http_404?
          http_status == 404
        end

        # Check if the error is an "already exists" error from Twirp
        # Maps to HTTP 409 Conflict based on Twirp error code mapping
        # Used when attempting to create a resource that already exists, such as a cost center with a duplicate name
        def already_exists?
          original_error.is_a?(Twirp::Error) && original_error.code == :already_exists
        end

        # Check if the error is a "resource exhausted" error from Twirp
        # Maps to HTTP 429 Too Many Requests based on Twirp error code mapping
        # Used when a resource limit is reached, such as the maximum number of active cost centers (1000) per enterprise
        def resource_exhausted?
          original_error.is_a?(Twirp::Error) && original_error.code == :resource_exhausted
        end

        # HTTP status based on code to status mapping defined in twirp-ruby
        # https://github.com/arthurnn/twirp-ruby/blob/a61951f2df21ccda465e9fd4c4f15d895d2fac23/lib/twirp/error.rb#L16-L38
        # TODO: open a PR in twirp-ruby to expose the HTTP status in Twirp::Error directly
        def http_status
          if original_error.is_a?(Twirp::Error) && Twirp::Error.valid_code?(original_error.code)
            Twirp::ERROR_CODES_TO_HTTP_STATUS.fetch(original_error.code)
          else
            500
          end
        end
      end
    end
  end
end
