# typed: true
# frozen_string_literal: true

require "twirp"

module GitHub
  module Twirp
    class DependabotPullRequests
      class TwirpError < StandardError
        extend T::Sig

        sig { params(message: String, error: ::Twirp::Error).returns(TwirpError) }
        def self.for_error(message, error)
          return TransientTwirpError.new(message, error) if ::Twirp::ERROR_CODES_TO_HTTP_STATUS[error.code] >= 500

          TwirpError.new(message, error)
        end

        delegate :code, :meta, to: :@error

        attr_reader :error

        sig { params(message: String, err: ::Twirp::Error).void }
        def initialize(message, err)
          @error = err
          @details = err.msg
          super(message)
        end

        sig { returns(String) }
        def details
          error.msg
        end

        sig { returns(Integer) }
        def http_status_code
          ::Twirp::ERROR_CODES_TO_HTTP_STATUS[code]
        end
      end

      class TransientTwirpError < TwirpError; end
    end
  end
end
