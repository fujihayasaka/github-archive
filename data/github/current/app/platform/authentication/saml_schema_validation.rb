# typed: true
# frozen_string_literal: true

module Platform
  module Authentication
    module SamlSchemaValidation
      SCHEMA_DIR = File.expand_path("../saml_schemas", __FILE__)
      PROTOCOL_SCHEMA_FILE_NAME = "saml20protocol_schema.xsd"
      ALLOWED_ATTRIBUTES = [
        # Element name, attribute name.
        %w(SignatureMethod Algorithm),
        %w(CanonicalizationMethod Algorithm),
        %w(Transform Algorithm),
        %w(DigestMethod Algorithm),
        %w(AuthnStatement AuthnInstant),
        %w(Assertion IssueInstant),
        %w(Assertion Version)
      ].freeze

      @@provider_schemas = {}

      def self.validate_schema(saml_response, issuers)
        return unless schema = get_schema(issuers)

        schema.validate(Nokogiri::XML(saml_response))
      rescue Nokogiri::XML::SyntaxError => e
        GitHub.logger.error(
          "info.message" => "SAML schema validation error",
          "gh.error.message" => e.message,
        )
      end

      def self.sanitize_saml_response(raw_saml)
        doc = Nokogiri::XML(raw_saml, &:noblanks)

        # This replaces all text nodes and attribute values with "SANITIZED", with the exception of the allow list.
        doc.xpath("//text()|//*/@*").each do |node|
          next if node.is_a?(Nokogiri::XML::Attr) && ALLOWED_ATTRIBUTES.include?([node.parent.name, node.name])
          node.content = "SANITIZED"
        end

        doc.to_xml(indent: 2)
      end

      private_class_method def self.get_schema(issuers)
        return unless provider_schema_path = get_schema_dir(issuers)

        return @@provider_schemas[provider_schema_path] if @@provider_schemas[provider_schema_path].present?

        Dir.chdir(provider_schema_path) do
          @@provider_schemas[provider_schema_path] = Nokogiri::XML::Schema(File.read(PROTOCOL_SCHEMA_FILE_NAME))
        end
      end

      private_class_method def self.get_schema_dir(issuers)
        provider_types = Business::SamlProvider::ProviderTypeDependency::PROVIDER_TYPE_REGEX

        pattern = provider_types.keys.find do |pattern|
          pattern.match(issuers.first)
        end

        provider = provider_types[pattern]

        return unless provider

        # provider-based schemas are stored in a subdirectory of the schema_dir using the provider name
        "#{SCHEMA_DIR}/#{provider}"
      end

      private

      def tag_saml_responses(saml_response)
        issuers = saml_response.issuers.map(&:strip).uniq
        validation_errors = Platform::Authentication::SamlSchemaValidation.validate_schema(saml_response.response, issuers)
        sanitized_saml_response = Platform::Authentication::SamlSchemaValidation.sanitize_saml_response(saml_response.response)
        has_doctype = Nokogiri::XML(saml_response.response).internal_subset.present?

        GitHub.logger.info(
          "info.message" => "SAML schema tagging",
          "gh.target.type" => @target&.class&.name,
          "gh.target.id" => @target&.id,
          "gh.target.slug" => @target&.to_s,
          "gh.saml.response.issuers" => issuers,
          "gh.saml.schema.validation.errors" => validation_errors,
          "gh.saml.schema.validated" => validation_errors.present?,
          "gh.saml.sanitized_response" => Base64.encode64(sanitized_saml_response),
          "gh.saml.has_doctype" => has_doctype
        )
      end
    end
  end
end
