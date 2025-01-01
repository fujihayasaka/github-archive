# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    class X509Certificate < Platform::Scalars::Base
      description "A valid x509 certificate string"

      def self.coerce_input(value, context)
        if value.nil?
          nil
        else
          OpenSSL::X509::Certificate.new(value)
        end
      rescue OpenSSL::X509::CertificateError
        nil
      end

      def self.coerce_result(value, context)
        value.to_s
      end
    end
  end
end
