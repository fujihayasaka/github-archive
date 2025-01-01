# typed: true
# frozen_string_literal: true

require "scientist"

module Platform
  module Authorization
    # This class is responsible for authorizing API requests.
    #
    # Because we support multiple types of tokens, e.g: PATS, [user|server]-to-server, etc.
    # we have to run specific authorization rules depending on the current request context.
    #
    # To address this concern, the class uses the current context to authorize _this_ request
    # by delegating the actual authorization business logic to a specialized authorizer.
    #
    # Instances of this class are created an used on endpoints :control_access runs.
    #
    # The class is modular in the sense that specialized Authorizers can be "plugged" as long
    # as they implement the #authorize? interface.
    class ProgrammaticAccessAuthorizer
      include Scientist

      STATS_KEY = "platform.authorization.programmatic_access_authorizer.distribution"

      attr_reader :authorizer

      def initialize(context)
        @result = ExecutionLog.failed.enable!
        @authorizer = build_authorizer(context)
      end

      def authorize(verb, options)
        @result.context[:verb] = verb
        @result.context[:resource] = options[:resource]

        with_instrumentation do
          @result.decision(:success) if authorizer.authorized?(verb, options)
          @result
        end
      end

      private

      def build_authorizer(context)
        authorizer_class =
          if context.integration_bot_request?
            ServerToServerAuthorizer
          elsif context.global_integration_user_request?
            GlobalUserToServerAuthorizer
          elsif context.integration_user_request?
            UserToServerAuthorizer
          elsif context.user_programmatic_access_request?
            UserProgrammaticAccessAuthorizer
          elsif context.user_request?
            UserWithScopesAuthorizer
          else
            NullAuthorizer
          end

        @result.stepped(
          name: "authorizer selected",
          reason: authorizer_class.name
        )
        authorizer_class.new_from_context(context, @result)
      end

      def with_instrumentation(&block)
        start = GitHub::Dogstats.monotonic_time
        result = block.call

        GitHub.dogstats.distribution(
          STATS_KEY,
          GitHub::Dogstats.duration(start),
          tags: [
            "result:#{result.status}",
            "authorizer_type:#{authorizer.class.name.demodulize.underscore}"
          ]
        )

        result
      end
    end
  end
end
