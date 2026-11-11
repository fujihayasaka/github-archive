# typed: strict
# frozen_string_literal: true

module ReactPayload
  class Base
    extend T::Helpers

    abstract!

    sig { abstract.returns(T.any(String, T::Hash[String, T.untyped], T::Hash[Symbol, T.untyped])) }
    def payload; end

    sig { abstract.returns(String) }
    def route_id; end

    # The ssr_response is only needed for VoltronPartial. We add it here to keep the same signature
    # for all subclasses.
    sig { params(_ssr_response: T.nilable(Alloy::Response)).returns(T.any(String, T::Hash[String, T.untyped], T::Hash[Symbol, T.untyped])) }
    def resolve(_ssr_response = nil)
      timer = Timer.start
      result = payload
      GitHub.dogstats.distribution("react.payload.resolve.time", timer.elapsed_ms, tags: ["route_id:#{route_id}"])

      result
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def as_json
      {
        self.route_id => resolve,
      }
    end

    sig { returns(T::Boolean) }
    def partial?
      false
    end

    sig { returns(T::Boolean) }
    def async?
      false
    end
  end

  class Partial < Base
    abstract!

    sig { params(partial_proc: T.proc.returns(String)).void }
    def initialize(partial_proc)
      @partial_proc = partial_proc
    end

    sig { override.returns(String) }
    def payload
      @payload ||= T.let(@partial_proc.call, T.nilable(String))
    end

    sig { returns(T::Boolean) }
    def async?
      true
    end

    # Only send a marker for partials that will be replaced by Rails.
    # We do this to avoid sending large payloads to Alloy and possibly hitting its limit.
    sig { returns(String) }
    def marker
      @marker ||= T.let("__rails-partial-#{SecureRandom.uuid}__", T.nilable(String))
    end

    sig { returns(T::Boolean) }
    def partial?
      true
    end
  end

  class VoltronPartial < Partial
    abstract!

    sig { params(fragment_id: String, partial_proc: T.proc.returns(String), voltron_enabled: T::Boolean).void }
    def initialize(fragment_id:, partial_proc:, voltron_enabled: false)
      @fragment_id = fragment_id
      @partial_proc = partial_proc
      @voltron_enabled = voltron_enabled
    end

    sig { override.returns(String) }
    def payload
      @payload ||= @partial_proc.call
    end

    sig { params(ssr_response: T.nilable(Alloy::Response)).returns(String) }
    def resolve(ssr_response = nil)
      return payload if !@voltron_enabled || ssr_response.nil? || !ssr_response.success?

      "<viewproxy-fragment id=\"#{@fragment_id}\"></viewproxy-fragment>"
    end

    sig { returns(T::Boolean) }
    def async?
      !@voltron_enabled
    end
  end
end
