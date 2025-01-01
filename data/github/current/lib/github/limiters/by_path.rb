# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters

    # Public: Limit any request with matching PATH_INFO.
    class ByPath < GitHub::Limiter
      include GitHub::Middleware::Constants

      def initialize(*paths)
        super("path")
        @paths = paths
      end

      def start(request)
        @paths.include?(request.path_info) ? LIMITED : OK
      end
    end
  end
end
