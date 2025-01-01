# frozen_string_literal: true

require 'jwt'

module Vonage
  class JWT
    attr_accessor :generator, :typ, :iat

    def initialize(params = {})
      @generator = params.fetch(:generator)
      @typ = params.fetch(:typ, 'JWT')
      @iat = params.fetch(:iat, Time.now.to_i)
    end

    def generate
      ::JWT.encode(to_payload, generator.private_key, generator.alg, header_fields={typ: typ})
    end

    def to_payload
      hash = {
        iat: iat,
        jti: generator.jti,
        exp: generator.exp || iat + generator.ttl,
        application_id: generator.application_id
      }
      hash.merge!(generator.paths) if generator.paths
      hash.merge!(sub: generator.subject) if generator.subject
      hash.merge!(nbf: generator.nbf) if generator.nbf
      hash.merge!(generator.additional_claims) if !generator.additional_claims.empty?
      hash
    end

    def self.decode(token, secret = nil, verify = true, opts = {}, &block)
      ::JWT.decode(token, secret, verify, opts, &block)
    end

    def self.verify_signature(token, signature_secret, algorithm)
      begin
        decode(token, signature_secret, true, {algorithm: algorithm})
        return true
      rescue ::JWT::VerificationError
        return false
      end
    end
  end
end
