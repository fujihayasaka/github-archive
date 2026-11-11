# typed: strict
# frozen_string_literal: true

module CopilotSessions
  # This is meant to model the underlying API response for listing sessions as children,
  # which is different from the full session object. This should match CAPI's response shape of enumerating
  # sessions for a resource.
  class PartialAgentSession
    sig do
      params(
        sessions: T.nilable(T::Array[T::Hash[String, T.untyped]])
      ).returns(T::Array[PartialAgentSession])
    end
    def self.from_raw(sessions)
      return [] unless sessions

      sessions.map do |session|
        new(session.with_indifferent_access)
      end
    end

    sig { returns(T::Hash[String, T.untyped]) }
    attr_reader :session

    sig { params(session: T::Hash[String, T.untyped]).void }
    def initialize(session)
      @session = session
    end

    sig { returns(String) }
    def id
      session["id"]
    end

    sig { returns(String) }
    def last_updated_at
      # Support both the legacy "last_updated_at" field and the new "updated_at" field
      # used when copilot_task_api_github_rest_style is enabled.
      value = session["updated_at"] || session["last_updated_at"]

      # The /agents/resource CAPI endpoint will return last_updated_at as a epoch while
      # /agents/sessions/resources returns a ISO-8601 formatted time so we have to handle both cases.
      if value.is_a?(Integer)
        Time.at(value).utc.iso8601
      else
        value
      end
    end

    sig { returns(String) }
    def state
      session["state"]
    end
  end
end
