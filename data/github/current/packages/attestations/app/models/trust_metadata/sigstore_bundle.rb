# typed: true
# frozen_string_literal: true

module TrustMetadata
  class SigstoreBundle
    attr_reader :data, :predicate_type

    sig { params(data: T::Hash[String, T.untyped]).void }
    def initialize(data)
      @data = data
      @predicate_type = dsse_envelope_payload["predicateType"]
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def dsse_envelope_payload
      dsse_envelope = data["dsseEnvelope"]
      return {} unless dsse_envelope.is_a?(Hash)

      envelope_payload = dsse_envelope["payload"]
      return {} unless envelope_payload.is_a?(String)

      begin
        decoded = Base64.decode64(envelope_payload)
        parsed = JSON.parse(decoded)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end
    end

    sig { params(opt: T.nilable(T::Hash[T.untyped, T.untyped])).returns(T::Hash[Symbol, T.untyped]) }
    def as_json(opt = nil)
      data
    end

    sig { returns(T.nilable(T::Boolean)) }
    def valid?
      data["mediaType"].try(:index, "vnd.dev.sigstore.bundle") &&
        predicate_type.present?
    end

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      self.data == other.try(:data)
    end
  end
end
