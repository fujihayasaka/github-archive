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
        %w(Assertion Version),
        %w(AttributeValue type)
      ].freeze

      @@provider_schemas = {}

      def self.validate_schema(saml_response, issuer, validate_all_providers = false)
        return unless schema = get_schema(issuer, validate_all_providers)
        doc = Nokogiri::XML(saml_response)

        if doc.internal_subset.present?
          return ["DOCTYPE not allowed in SAML response"]
        end

        if doc.errors.any?
          GitHub.logger.error(
            "info.message" => "Error parsing SAML response",
            "gh.errors" => doc.errors.to_json,
          )

          return doc.errors
        end

        schema.validate(doc)
      rescue StandardError => e
        GitHub.logger.error(
          "info.message" => "SAML schema validation error",
          "gh.error.message" => e.message,
        )
        [e.message]
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

      def self.propagate_provider_errors?(issuer)
        !get_schema(issuer).nil?
      end

      private_class_method def self.get_schema(issuer, validate_all_providers = false)
        return unless provider_schema_path = get_schema_dir(issuer, validate_all_providers)

        return @@provider_schemas[provider_schema_path] if @@provider_schemas[provider_schema_path].present?

        Dir.chdir(provider_schema_path) do
          @@provider_schemas[provider_schema_path] = Nokogiri::XML::Schema(File.read(PROTOCOL_SCHEMA_FILE_NAME))
        end
      end

      private_class_method def self.get_schema_dir(issuer, validate_all_providers = false)
        return SCHEMA_DIR if validate_all_providers

        provider_types = Business::SamlProvider::ProviderTypeDependency::PROVIDER_TYPE_REGEX

        pattern = provider_types.keys.find do |pattern|
          pattern.match(issuer)
        end

        provider = provider_types[pattern]

        return unless provider

        SCHEMA_DIR
      end

      private

      def tag_saml_responses(saml_response)
        return unless GitHub.enterprise? || FeatureFlag.vexi.enabled?(:saml_strict_schema_validation, @target, default: false)

        issuers = saml_response.issuers.map(&:strip).uniq
        issuer = issuers.size > 1 ? issuers.second : issuers.first

        validate_all_providers = FeatureFlag.vexi.enabled?(:validate_all_saml_schemas, @target, default: false) ? true : nil

        validation_errors = Platform::Authentication::SamlSchemaValidation.validate_schema(saml_response.response, issuer, validate_all_providers)
        sanitized_saml_response = Platform::Authentication::SamlSchemaValidation.sanitize_saml_response(saml_response.response)

        if (validation_errors.nil? || validation_errors.empty?) && saml_response.decrypted_document.present?
          validation_errors = Platform::Authentication::SamlSchemaValidation.validate_schema(saml_response.decrypted_document.to_s, issuer, validate_all_providers)
        end

        has_doctype = Nokogiri::XML(saml_response.response).internal_subset.present?

        # always log in non-GHES environments or when debug logging is enabled in GHES
        if !GitHub.enterprise? || GitHub.config.get("saml.debug_logging_enabled") == "true"
          GitHub.logger.info(
            "info.message" => "SAML schema tagging",
            "gh.target.type" => @target&.class&.name,
            "gh.target.id" => @target&.id,
            "gh.target.slug" => @target&.to_s,
            "gh.saml.response.issuers" => issuers,
            "gh.saml.schema.validation.errors" => validation_errors,
            "gh.saml.schema.validated" => !validation_errors.nil?,
            "gh.saml.sanitized_response" => Base64.encode64(sanitized_saml_response),
            "gh.saml.has_doctype" => has_doctype
          )
        end

        return if validation_errors.nil?
        return if validation_errors.empty?
        if FeatureFlag.vexi.enabled?(:validate_all_saml_schemas, @target, default: false)
          return unless Platform::Authentication::SamlSchemaValidation.propagate_provider_errors?(issuer)
        end

        saml_response.errors = validation_errors.map(&:to_s)
        validation_errors
      ensure
        provider = Business::SamlProvider::ProviderTypeDependency.find_provider_type_from_issuer(issuer)

        # we expect that:
        # 1. validation_errors will be nil when we did not run validations
        # 2. validation_errors will be an empty array when the schema is valid
        # 3. validation_errors will be an array containing errors when the schema is invalid
        validation_result = if validation_errors.nil?
          "not_validated"
        else
          validation_errors.empty? ? "valid" : "invalid"
        end

        GitHub.dogstats.increment(
          "saml.strict_schema_validation",
          tags: [
            "result:#{validation_result}",
            "provider:#{provider}"
          ]
        )
      end
    end
  end
end
