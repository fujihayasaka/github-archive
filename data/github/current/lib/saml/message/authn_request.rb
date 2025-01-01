# typed: true
# frozen_string_literal: true

module SAML
  class Message
    # AuthnRequest is the request sent from an SP to and idP to initiate an auth
    # flow.
    #
    # http://www.schemacentral.com/sc/saml2/e-samlp_AuthnRequest.html
    class AuthnRequest < Message
      include SAML::Shared::Issuer
      include SAML::Shared::Request

      class FipsError < StandardError; end

      attr_accessor :assertion_consumer_service_url
      attr_accessor :name_identifier_format
      attr_accessor :passive
      attr_accessor :protocol_binding
      attr_accessor :expiry
      attr_accessor :signature_method
      attr_accessor :digest_method
      attr_accessor :force_authn

      alias_method :passive?, :passive

      def self.parse(doc, signatures = nil)
        authn_request = doc.xpath("//samlp:AuthnRequest")
        request_id = authn_request.attribute("ID").text
        destination = authn_request.attribute("Destination").text
        passive = authn_request.attribute("IsPassive").text == "true"
        protocol_binding = authn_request.attribute("ProtocolBinding").text
        assertion_consumer_service_url = authn_request.attribute("AssertionConsumerServiceURL").text
        issue_instant = authn_request.attribute("IssueInstant").text

        issuer = doc.xpath("//samlp:AuthnRequest/saml:Issuer")
        conditions = doc.at_xpath("//samlp:AuthnRequest/saml:Conditions")
        expiry = conditions.attribute("NotOnOrAfter") || conditions.attribute("NotBefore")
        name_id_policy = doc.xpath("//samlp:AuthnRequest/samlp:NameIDPolicy")
        name_identifier_format = name_id_policy && name_id_policy.attribute("Format").try(:value)

        new({
          id: request_id,
          destination: destination,
          passive: passive,
          protocol_binding: protocol_binding,
          assertion_consumer_service_url: assertion_consumer_service_url,
          issue_instant: issue_instant && DateTime.parse(issue_instant),
          issuer: issuer && issuer.text,
          expiry: expiry && expiry.text && DateTime.parse(expiry.text),
          name_identifier_format: name_identifier_format,
        })
      end

      # Optional attributes
      #
      #   :assertion_consumer_service_url - SP endpoint for idP to POST auth responses to
      #   :id - unique request id. Automatically generated if not specified
      #   :destination - intended idP endpoint for this request
      #   :issuer - SP descriptor
      #   :name_identifier_format - defaults to "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"
      #   :passive - defaults to false
      #   :protocol_binding - defaults to "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
      #   :expiry - The date time the request expires in
      def initialize(options = {})
        super
        self.name_identifier_format ||= "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"
        self.passive ||= false
        self.protocol_binding ||= "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
      end

      # Internal: Generate `Conditions` element with Nokogiri::XML::Builder
      # `builder`. Returns nothing.
      def generate_conditions(builder)
        return unless expiry
        xml_attrs = { "NotBefore" => format_time(expiry - GitHub::Authentication::SAML::AUTHN_REQUEST_TIMEOUT), "NotOnOrAfter" => format_time(expiry) }
        builder["saml"].Conditions(xml_attrs)
      end

      def build_document
        doc = Nokogiri::XML::Builder.new do |xml|
          root_attributes = {
            "xmlns:samlp"     => "urn:oasis:names:tc:SAML:2.0:protocol",
            "xmlns:saml"      => "urn:oasis:names:tc:SAML:2.0:assertion",
            "ID"              => self.id,
            "IssueInstant"    => format_time(self.issue_instant),
            "Version"         => version,
          }
          root_attributes["Destination"] = self.destination if self.destination.present?
          root_attributes["IsPassive"]   = self.passive unless self.passive.nil?
          root_attributes["ProtocolBinding"] = self.protocol_binding if self.protocol_binding.present?
          root_attributes["AssertionConsumerServiceURL"] = self.assertion_consumer_service_url if self.assertion_consumer_service_url.present?
          root_attributes["ForceAuthn"] = self.force_authn if self.force_authn.present?

          xml["samlp"].AuthnRequest(root_attributes) do |xml|
            generate_issuer(xml)

            # We use HTTP Redirect bindings, this has to be external
            # xml["ds"].Signature("xmlns:ds" => "http://www.w3.org/2000/09/xmldsig#") do |xml|
            #   xml["ds"].SignedInfo do |xml|
            #     xml["ds"].CanonicalizationMethod("Algorithm" => "http://www.w3.org/2001/10/xml-exc-c14n#")
            #     xml["ds"].SignatureMethod("Algorithm" => self.signature_method)
            #     xml["ds"].Reference("URI" => "##{self.id}") do |xml|
            #       xml["ds"].Transforms do |xml|
            #         xml["ds"].Transform("Algorithm" => "http://www.w3.org/2000/09/xmldsig#enveloped-signature")
            #         xml["ds"].Transform("Algorithm" => "http://www.w3.org/2001/10/xml-exc-c14n#")
            #       end
            #       xml["ds"].DigestMethod("Algorithm" => self.digest_method)
            #       xml["ds"].DigestValue
            #     end
            #   end
            #   xml["ds"].SignatureValue
            #end

            if self.name_identifier_format
              xml["samlp"].NameIDPolicy({
                "AllowCreate" => true,
                "Format"      => self.name_identifier_format,
              })
            end

            generate_conditions(xml)
          end
        end.doc
      end

      def self.signature_string(params)
        out = ""
        if params["SAMLRequest"]
          out = "SAMLRequest=#{::CGI::escape(params["SAMLRequest"])}"
        else
          out = "SAMLResponse=#{::CGI::escape(params["SAMLResponse"])}"
        end
        if params["RelayState"]
          out = "#{out}&RelayState=#{::CGI::escape(params["RelayState"])}"
        end
        "#{out}&SigAlg=#{::CGI::escape(params["SigAlg"])}"
      end

      # To construct the signature, a string consisting of the concatenation of the RelayState (if present),
      # SigAlg, and SAMLRequest (or SAMLResponse) query string parameters (each one URLencoded)
      # is constructed in one of the following ways (ordered as below):
      # SAMLRequest=value&RelayState=value&SigAlg=value
      # SAMLResponse=value&RelayState=value&SigAlg=value
      # The resulting string of bytes is the octet string to be fed into the signature algorithm. Any other
      # content in the original query string is not included and not signed.
      # The signature value MUST be encoded using the base64 encoding (see RFC 2045 [RFC2045]) with
      # any whitespace removed, and included as a query string parameter named Signature. Note that
      # some characters in the base64-encoded signature value may themselves require URL-encoding
      # before being added.
      def query_signature(options = {})
        raise "options[:data] must be specified" unless options && options[:data]
        key = options[:private_key]
        raise "Need private key" unless key
        signature_alg = options[:data]["SigAlg"]
        raise "Need a signature algorithm" unless signature_alg
        data = self.class.signature_string(options[:data])
        digest = self.class.signature_to_digest(signature_alg)
        Base64.strict_encode64(key.sign(digest, data))
      end

      def self.signature_to_digest(sig_alg)
        case sig_alg
        when "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
          OpenSSL::Digest::SHA256.new
        when "http://www.w3.org/2001/04/xmldsig-more#rsa-sha384"
          OpenSSL::Digest::SHA384.new
        when "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512"
          OpenSSL::Digest::SHA512.new
        else
          if GitHub.fips_mode?
            raise FipsError.new("SHA1 algorithm is not allowed with FIPS mode.")
          else
            OpenSSL::Digest::SHA1.new # rubocop:disable GitHub/InsecureHashAlgorithm
          end
        end
      end
    end
  end
end
