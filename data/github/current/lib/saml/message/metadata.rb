# typed: true
# frozen_string_literal: true

module SAML
  class Message
    # SAML Metadata describes configuration about relying parties (RP) such as
    # service providers (SP), and identity providers (idP).
    #
    # http://www.schemacentral.com/sc/saml2/e-md_EntityDescriptor.html
    class Metadata < Message
      attr_accessor :name_identifier_format
      attr_accessor :sign_assertions
      attr_accessor :sign_authn_requests
      attr_accessor :encrypted_assertions
      attr_accessor :expiry

      DEFAULT_EXPIRY = 5 * 60 # 5 minutes

      # Public: We don't consume metadata yet, so I haven't bothered with
      # implementing this.
      def self.parse(doc, signatures = nil)
        raise NotImplementedError
      end

      # Required attributes
      #
      #  :assertion_consumer_service_url - SP endpoint for idP to POST auth responses to
      #
      # Optional attributes
      #
      #  :assertion_consumer_logout_service_url - SP endpoint for idP to POST logout responses to
      #  :sign_assertions                       - defaults to false
      #  :sign_authn_requests                   - defaults to true if an SP signing certificate is configured
      #  :encrypted_assertions                  - defaults to false
      #  :issuer
      #  :name_identifier_format                - defaults to "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"
      #  :sp_signing_certificate                - optional, but required if single logout is configured
      #  :sp_encryption_certificate             - optional, but required if encrypt assertions is configured
      #  :expiry                                - defaults to 5 minutes
      def initialize(options = {})
        self.sign_assertions = !!options[:sign_assertions]
        self.encrypted_assertions = !!options[:encrypted_assertions]
        self.sign_authn_requests = options.fetch(:sign_authn_requests, !!options[:sp_signing_certificate])
        self.name_identifier_format = options[:name_identifier_format] || "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"
        self.expiry = options.fetch(:expiry, DEFAULT_EXPIRY).to_i
        @options = options
      end

      def valid_until
        format_time(Time.now + expiry)
      end

      def build_document
        document = Nokogiri::XML::Builder.new do |xml|
          root_attributes = {
            "xmlns:md" => "urn:oasis:names:tc:SAML:2.0:metadata",
            "validUntil" => valid_until,
          }
          root_attributes["entityID"] = @options[:issuer] if @options[:issuer]

          xml["md"].EntityDescriptor(root_attributes) do |xml|
            xml.SPSSODescriptor({
              "protocolSupportEnumeration" => "urn:oasis:names:tc:SAML:2.0:protocol",
              "AuthnRequestsSigned"  => self.sign_authn_requests,
              "WantAssertionsSigned" => self.sign_assertions,
            }) do

              if self.encrypted_assertions && @options[:sp_encryption_certificate]
                encryption_certificate = Base64.strict_encode64(@options[:sp_encryption_certificate])
                xml["md"].KeyDescriptor({ "use" => "encryption" }) do
                  xml.KeyInfo({ "xmlns:ds" => "http://www.w3.org/2000/09/xmldsig#" }) do
                    xml.parent.namespace = xml.parent.namespace_definitions.first
                    xml["ds"].X509Data do
                      xml["ds"].X509Certificate(encryption_certificate)
                    end
                  end
                end
              end

              if @options[:sp_signing_certificate]
                signing_certificate = Base64.strict_encode64(@options[:sp_signing_certificate])
                xml["md"].KeyDescriptor({ "use" => "signing" }) do
                  xml.KeyInfo({ "xmlns:ds" => "http://www.w3.org/2000/09/xmldsig#" }) do
                    xml.parent.namespace = xml.parent.namespace_definitions.first
                    xml["ds"].X509Data do
                      xml["ds"].X509Certificate(signing_certificate)
                    end
                  end
                end
              end

              if @options[:assertion_consumer_logout_service_url]
                xml["md"].SingleLogoutService({
                    "Binding"          => "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST",
                    "Location"         => @options[:assertion_consumer_logout_service_url],
                    "ResponseLocation" => @options[:assertion_consumer_logout_service_url],
                    "isDefault"        => true,
                    "index"            => 0,
                })
              end

              if self.name_identifier_format
                xml["md"].NameIDFormat(self.name_identifier_format)
              end

              if @options[:assertion_consumer_service_url]
                xml["md"].AssertionConsumerService({
                    "Binding"   => "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST",
                    "Location"  => @options[:assertion_consumer_service_url],
                    "isDefault" => true,
                    "index"     => 0,
                })
              end
            end  # /SPSSODescriptor
          end
        end.doc
      end

      # Private: Returns false if `document` is invalid SAML Metadata xml
      def validate_schema
        # Reason we don't memoize this is because nokogiri needs the relative
        # paths to find the other schema definitions.
        Dir.chdir(SCHEMA_DIR) do
          schema = Nokogiri::XML::Schema(File.read("saml-schema-metadata-2.0.xsd"))
          self.errors += schema.validate(document)
        end
      end

    end
  end
end
