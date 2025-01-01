# typed: false
# frozen_string_literal: true

require "github"
require "github/after_response"

module GitHub
  module Config
    module AfterResponse

      def self.extended(base)
        class << base
          # What happens when an exception occurs in an after_response handler?
          attr_accessor :after_response_raise_on_exception
          alias after_response_raise_on_exception? after_response_raise_on_exception

          # Is the GitHub after_response middleware system enabled?
          # Default true, but set AFTER_RESPONSE_MIDDLEWARE_ENABLED=0 to disable
          attr_accessor :after_response_middleware_enabled

          # if our ENV is set, use that to control whether this is enabled,
          # otherwise use the ivar from the above attr_accessor.
          if ENV.key?("after_response_middleware_enabled")
            def after_response_middleware_enabled?
              return @env_override_after_response_middleware_enabled if defined?(@env_override_after_response_middleware_enabled)
              @env_override_after_response_middleware_enabled = (ENV["AFTER_RESPONSE_MIDDLEWARE_ENABLED"] == "1")
            end
          else
            alias after_response_middleware_enabled? after_response_middleware_enabled
          end
        end

        # Default is raise so any issues are highly visible in dev and test.
        # We will override this in prod to false for safety (notify failbot only)
        base.after_response_raise_on_exception = true

        # This can be disabled by setting AFTER_RESPONSE_MIDDLEWARE_ENABLED=0 in env.
        base.after_response_middleware_enabled = true
      end

      def after_response
        @after_response ||= NullAfterResponse.new(nil)
      end

      # Public: Override the Afterresponse instance within the given block
      def with_after_response(temp_after_response, &block)
        old_after_response = after_response

        begin
          @after_response = temp_after_response
          yield
        ensure
          @after_response  = old_after_response
        end
      end

      class NullAfterResponse
        def initialize(env)
        end

        def enabled?
          false
        end

        def perform(name, &block)
        end
      end
    end
  end

  extend Config::AfterResponse
end
