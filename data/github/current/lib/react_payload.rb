# typed: strict
# frozen_string_literal: true

module ReactPayload
  # Payloads may resolve to a String, a Hash, or a protobuf message (encoded as
  # proto3-JSON by yajl via `#to_json`, like other non-native payload objects).
  PayloadValue = T.type_alias do
    T.any(String, T::Hash[String, T.untyped], T::Hash[Symbol, T.untyped], Google::Protobuf::MessageExts)
  end

  class Base
    extend T::Helpers

    abstract!

    sig { abstract.returns(PayloadValue) }
    def payload; end

    sig { abstract.returns(String) }
    def route_id; end

    # The ssr_response is only needed for VoltronPartial. We add it here to keep the same signature
    # for all subclasses.
    sig { params(_ssr_response: T.nilable(Alloy::Response)).returns(PayloadValue) }
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

  # Marker base for route payloads backed by a protobuf message. Subclasses
  # override `payload` to return the proto message directly (yajl encodes it as
  # proto3-JSON). The controller signals proto routes via the `X-Proto-JSON`
  # header (soft-nav JSON) or `embeddedData.meta.protoRoutes` (first-paint HTML)
  # so the client decodes them with the matching schema.
  class Proto < Base
    abstract!
  end

  # A generic deferred payload. Its content is produced lazily by a proc and is resolved
  # while the SSR render is in-flight. Unlike Partial, Async payloads are not represented by a
  # marker in the SSR HTML; they are always merged into the embedded data payload after SSR.
  class Async < Base
    abstract!

    sig { params(async_proc: T.proc.returns(T.any(String, T::Hash[String, T.untyped], T::Hash[Symbol, T.untyped]))).void }
    def initialize(async_proc)
      @async_proc = async_proc
    end

    sig { override.returns(T.any(String, T::Hash[String, T.untyped], T::Hash[Symbol, T.untyped])) }
    def payload
      @payload ||= T.let(@async_proc.call, T.nilable(T.any(String, T::Hash[String, T.untyped], T::Hash[Symbol, T.untyped])))
    end

    sig { returns(T::Boolean) }
    def async?
      true
    end
  end

  class Partial < Async
    abstract!

    sig { params(async_proc: T.proc.returns(String)).void }
    def initialize(async_proc)
      @async_proc = async_proc
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
      @async_proc = partial_proc
      @voltron_enabled = voltron_enabled
    end

    sig { params(ssr_response: T.nilable(Alloy::Response)).returns(T.any(String, T::Hash[String, T.untyped], T::Hash[Symbol, T.untyped])) }
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
