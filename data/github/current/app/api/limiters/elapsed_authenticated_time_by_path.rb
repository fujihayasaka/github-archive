# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    class ElapsedAuthenticatedTimeByPath < ElapsedTimeByAuthenticationFingerprint
      IGNORED_PATHS = [
        %r{\A/rate_limit\z},
      ]

      attr_reader :path

      def initialize(name, max:, path:)
        super(name, max: max)

        @path = path
      end

      def record_finish(request)
        if self.class.twirp_request?(request)
          OK
        else
          increment_counter(request)
        end
      end

      def ignored?(request)
        IGNORED_PATHS.any? { |path_regex| request.path_info =~ path_regex }
      end

      protected

      def increment_counter(request)
        super if path == request.path_info
      end

      # Internal: has the request met or exceeded the limit?
      def at_limit?(request)
        super if path == request.path_info
      end

      def key(request)
        [super, path.parameterize].join(":")
      end
    end
  end
end
