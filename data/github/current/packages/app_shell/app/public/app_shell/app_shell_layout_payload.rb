# typed: strict
# frozen_string_literal: true

module AppShell
  class AppShellLayoutPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "appShellLayoutRoute"
    end

    sig { params(message: String).void }
    def initialize(message)
      @message = message
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def payload
      {
        someField: @message,
      }
    end
  end
end
