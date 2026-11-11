# typed: true
# frozen_string_literal: true

require "github/after_response"

module GitHub
  module Middleware
    class AfterResponse
      def initialize(app)
        @app = app
      end

      def call(env)
        if GitHub.after_response_middleware_enabled?
          after_response = GitHub::AfterResponse.new(env)

          GitHub.with_after_response(after_response) do
            @app.call(env)
          end
        else
          @app.call(env)
        end
      end
    end
  end
end
