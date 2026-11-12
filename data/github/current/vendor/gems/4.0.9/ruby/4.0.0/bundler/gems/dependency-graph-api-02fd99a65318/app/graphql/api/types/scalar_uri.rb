# typed: true
# frozen_string_literal: true

module API
  module Types
    class ScalarURI < Types::BaseScalar
      description "An RFC 3986, RFC 3987, and RFC 6570 (level 4) compliant URI string."

      def self.coerce_input(value, context)
        begin
          Addressable::URI.parse(value.strip) if value.is_a?(String)
        rescue Addressable::URI::InvalidURIError
        end
      end

      def self.coerce_result(value, context)
        value.to_s
      end
    end
  end
end
