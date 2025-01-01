# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    class ElapsedTimeByAuthenticationFingerprint < GitHub::Limiters::MemcachedWindow
      include Api::Limiters::TwirpHelpers

      REQUEST_STARTED_AT = "github.limiters.request_started_at"
      REQUEST_COST_KEY = "github.limiters.request_cost"

      IGNORED_PATHS = [
        %r{\A/rate_limit\z},
      ]

      def initialize(name = "time-based", max:)
        super(name, limit: max)
      end

      def ignored?(request)
        IGNORED_PATHS.any? { |path_regex| request.path_info =~ path_regex }
      end

      def start(request)
        request.env[REQUEST_STARTED_AT] = Time.now
        super
      end

      def record_finish(request)
        if self.class.twirp_request?(request)
          OK
        else
          increment_counter(request)
        end
      end

      protected

      def key(request)
        twirp_path = Api::Limiters::TwirpAuthenticationFingerprintByPath.twirp_path(request)

        if twirp_path
          client_name = Api::Internal::Twirp.client_name_from_header(request) || Api::Internal::Twirp::UNKNOWN_CLIENT_NAME
          "#{client_name}:#{fingerprint(request)}"
        else
          fingerprint(request)
        end
      end

      def fingerprint(request)
        Api::Middleware::RequestAuthenticationFingerprint.get(request.env).to_s
      end

      # The cost should be the number of milliseconds this request has taken.
      def cost(request)
        request_started_at = T.cast(request.env[REQUEST_STARTED_AT], Time)
        request_cost_in_sec = Time.now - request_started_at
        Integer((request_cost_in_sec) * 1_000)
      end
    end
  end
end
