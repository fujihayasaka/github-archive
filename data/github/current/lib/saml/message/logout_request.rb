# typed: true
# frozen_string_literal: true

require "date"

module SAML
  class Message
    # SAMLCore 3.7.1
    class LogoutRequest < Message
      include SAML::Shared::Issuer
      include SAML::Shared::Request

      attr_accessor :name_id
      attr_accessor :not_on_or_after
      attr_accessor :session_index

      def self.parse(doc, signatures = nil)
        # TODO: <saml:NameID> namespace `saml` isn't defined, only `samlp` is
        original_doc = doc.dup
        doc.remove_namespaces!

        condition = doc.root.attr("NotOnOrAfter")
        sig_nodeset = doc.root.xpath("//Signature")
        sig_present = sig_nodeset.size != 0
        new \
          id: doc.root.attr("ID"),
          destination: doc.root.attr("Destination"),
          issuer: doc.css("Issuer").text,
          name_id: doc.css("NameID").text,
          not_on_or_after: condition && DateTime.parse(condition),
          session_index: doc.css("SessionIndex").text,
          signed_document: sig_present && original_doc
      end

      # Required attributes
      #  :name_id
      #
      # Optional attributes
      #  :not_on_or_after - DateTime in utc request is valid
      #  :issuer          - String
      #  :session_index   - String
      def initialize(options = {})
        super
        self.destination ||= "https://not-implemented.invalid"
      end

      def build_document
        document = Nokogiri::XML::Builder.new do |xml|
          root_attributes = {
            "xmlns:samlp"  => "urn:oasis:names:tc:SAML:2.0:protocol",
            "xmlns:saml"   => "urn:oasis:names:tc:SAML:2.0:assertion",
            "ID"           => id,
            "Destination"  => destination,
            "IssueInstant" => format_time(issue_instant),
            "Version"      => version,
          }
          root_attributes["NotOnOrAfter"] = format_time(not_on_or_after) if not_on_or_after

          xml["samlp"].LogoutRequest(root_attributes) do |xml|
            generate_issuer(xml)

            xml["saml"].NameID(name_id) if name_id.present?
            xml["samlp"].SessionIndex(session_index) if session_index
          end
        end.doc
      end
    end
  end
end
