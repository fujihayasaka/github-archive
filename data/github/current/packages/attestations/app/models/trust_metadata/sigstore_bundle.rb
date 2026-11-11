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
      envelop_payload = data.dig("dsseEnvelope", "payload")

      if envelop_payload
        begin
          decoded = Base64.decode64(envelop_payload)
          JSON.load(decoded)
        rescue NoMethodError, JSON::ParserError
          {}
        end
      else
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
