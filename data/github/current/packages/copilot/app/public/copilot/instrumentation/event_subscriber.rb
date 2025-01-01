# typed: strict
# frozen_string_literal: true

# This class subscribes to the GitHub.instrument calls for Copilot for Business
module Copilot
  module Instrumentation
    class EventSubscriber
      sig do
        params(
          missing: T::Array[Symbol],
          payload: T.nilable(T::Hash[Symbol, String]),
          event_name: T.nilable(String),
        ).void
      end
      def self.log_missing(missing: [], payload: nil, event_name: nil)
        GitHub.logger.info(
          "Missing arguments for instrumentation",
          "code.function" => "perform",
          "code.namespace" => self.class.name,
          "gh.copilot.event.name" => event_name,
          "gh.copilot.event.args" => missing,
          "gh.copilot.event.payload" => payload,
        )
        GitHub.dogstats.increment("copilot.event_subscriber.missing.count")
      end
    end
  end
end
