# typed: true
# frozen_string_literal: true

require "onelogin/ruby-saml"

module Platform
  module Authentication
    class SAML
      class Authrequest < OneLogin::RubySaml::Authrequest
        def create_xml_document(settings)
          request_doc = super(settings)

          root = request_doc.root
          expiry = (GitHub::Authentication::SAML::AUTHN_REQUEST_TIMEOUT / 60).minutes.from_now
          conditions = root.add_element(
            "saml:Conditions",
            {
              "NotBefore" => (expiry - GitHub::Authentication::SAML::AUTHN_REQUEST_TIMEOUT).utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
              "NotOnOrAfter" => (expiry).utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            })
          request_doc
        end
      end

      class ExperimentResult
        attr_reader :invalid_part, :control_value, :candidate_value

        def initialize(namespace, urn, control, candidate)
          @namespace = namespace
          @urn = urn
          @control = Nokogiri::XML(control)
          @candidate = Nokogiri::XML(candidate)
        rescue Nokogiri::XML::SyntaxError
          @valid = false
          @invalid_part = "XML syntax"
        end

        def success?
          @valid
        end

        def validate(params)
          # check that any of the params is invalid
          params.any? do |param|
            is_valid = run_validation(
              xpath: param[:xpath],
              attribute: param[:attribute],
              presence: param[:presence],
            )
            return true unless is_valid
          end
        end

        private

        def run_validation(xpath:, attribute: nil, presence: false)
          return @valid = false if @control.nil? || @candidate.nil?

          control_node = @control.at_xpath(xpath, @namespace => @urn)
          candidate_node = @candidate.at_xpath(xpath, @namespace => @urn)

          return @valid = false if control_node.nil? || candidate_node.nil?

          if attribute.present?
            @control_value = control_node.get_attribute(attribute)
            @candidate_value = candidate_node.get_attribute(attribute)

            if presence
              @valid = @control_value.present? == @candidate_value.present?
            else
              @valid = @control_value == @candidate_value
            end
          else
            @control_value = control_node.text
            @candidate_value = candidate_node.text
            @valid = @control_value == @candidate_value
          end

          @invalid_part = if attribute.nil?
            xpath
          else
            "#{xpath}[@#{attribute}]"
          end

          @valid
        end
      end

      # Public: Generate a SAML metadata document for the given ACS and SP URLs.
      def self.generate_metadata(acs_url, sp_url)
        settings = OneLogin::RubySaml::Settings.new({
          sp_entity_id: sp_url,
          assertion_consumer_service_url: acs_url,
          security: {
            # these fields match what we currently return
            authn_requests_signed: false,
            want_assertions_signed: false,
          },
          name_identifier_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified",
          protocol_binding: "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST",
        })

        pretty_print = false
        valid_until = 5.minutes.from_now

        OneLogin::RubySaml::Metadata.new.generate(settings, pretty_print, valid_until)
      end

      # Public: Generate a SAML authentication request URL.
      #
      # authn_request - The SAML authentication request object.
      # relay_state - The relay state to be included in the request.
      # sso_url - The Single Sign-On (SSO) URL of the Identity Provider (IdP).
      # service_provider_url - The URL of the Service Provider (SP).
      # assertion_consumer_service_url - The URL where the IdP will send the SAML assertion.
      # signature_method - The method used to sign the request.
      # digest_method - The method used to create the digest of the request.
      # force_authn - Optional. Forces the IdP to re-authenticate the user.
      #
      # Returns the generated authentication request URL.
      def self.generate_authn_request_url(authn_request, relay_state, sso_url, service_provider_url,
        assertion_consumer_service_url, signature_method, digest_method, force_authn = nil)
        options = {
          idp_sso_service_url: sso_url,
          idp_sso_target_url: sso_url,
          sp_entity_id: service_provider_url,
          assertion_consumer_service_url: assertion_consumer_service_url,
          security: {
            signature_method: signature_method,
            digest_method: digest_method,
          },
          name_identifier_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified",
          protocol_binding: "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST",
          passive: false,
        }
        options[:force_authn] = force_authn if force_authn
        settings = OneLogin::RubySaml::Settings.new(options)
        authn_request_url = authn_request.create(settings, { RelayState: relay_state })
      end

      def self.process_response(raw_response, options)
        auth_result = consume(raw_response, options)

        if auth_result.success?
          auth_result.user_data = Platform::Provisioning::SamlUserData.load(
            auth_result.assertion,
            persist_attributes: @persist_attributes,
          )
        end

        auth_result
      end

      def self.metadata_match?(control, candidate)
        check_params = [
          { xpath: "//md:EntityDescriptor", attribute: "entityID" },
          { xpath: "//md:EntityDescriptor", attribute: "validUntil", presence: true },
          { xpath: "//md:AssertionConsumerService", attribute: "Location" },
          { xpath: "//md:AssertionConsumerService", attribute: "Binding" },
          { xpath: "//md:AssertionConsumerService", attribute: "isDefault" },
          { xpath: "//md:SPSSODescriptor", attribute: "protocolSupportEnumeration" },
          { xpath: "//md:SPSSODescriptor", attribute: "AuthnRequestsSigned" },
          { xpath: "//md:SPSSODescriptor", attribute: "WantAssertionsSigned" },
          { xpath: "//md:NameIDFormat" },
        ]

        namespace = "md"
        urn = "urn:oasis:names:tc:SAML:2.0:metadata"

        experiment_result = ExperimentResult.new(namespace, urn, control.to_s, candidate)
        experiment_result.validate(check_params)

        GitHub.logger.info(
          "info.message" => "SAML metadata comparison",
          "gh.saml.metadata_match" => experiment_result.success?,
          "gh.saml.metadata_mismatched_part" => experiment_result.invalid_part,
          "gh.saml.metadata_control_value" => experiment_result.control_value,
          "gh.saml.metadata_candidate_value" => experiment_result.candidate_value,
        )

        experiment_result.success?
      end

      private_class_method def self.consume(response, options)
        saml_settings = OneLogin::RubySaml::Settings.new(
          assertion_consumer_service_url: options[:assertion_consumer_service_url],
          sp_entity_id: options[:sp_url],
          idp_sso_service_url: options[:sso_url],
          idp_cert: options[:idp_certificate],
          security: {
            digest_method: options[:digest_method],
            signature_method: options[:signature_method],
          }
        )

        saml_response = OneLogin::RubySaml::Response.new(response, settings: saml_settings)

        unless saml_response.is_valid?
          return Platform::Authentication::SamlResult.invalid(saml_response)
        end

        if saml_response.success?
          Platform::Authentication::SamlResult.authorized(saml_response)
        else
          Platform::Authentication::SamlResult.unauthorized(saml_response)
        end
      rescue => err
        Platform::Authentication::SamlResult.invalid(errors: err.message)
      end
    end
  end
end
