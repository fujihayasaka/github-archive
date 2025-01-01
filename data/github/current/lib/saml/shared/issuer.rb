# typed: true
# frozen_string_literal: true

module SAML
  module Shared
    module Issuer
      extend ActiveSupport::Concern

      attr_accessor :issuer

      private

      # Internal: Generate `Issuer` element in Nokogiri::XML::Builder
      # `builder`. Returns nothing.
      def generate_issuer(builder)
        return unless issuer

        xml_attrs = { "xmlns:saml" => "urn:oasis:names:tc:SAML:2.0:assertion" }
        builder["saml"].Issuer(xml_attrs, issuer)
      end
    end
  end
end
