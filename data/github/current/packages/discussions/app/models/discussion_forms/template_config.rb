# typed: true
# frozen_string_literal: true

module DiscussionForms
  class TemplateConfig < StructuredTemplates::ConfigurationBase
    attr_reader :title

    OPTIONAL_KEYS = [
      { id: "title", type: "String" },
      { id: "body", type: "Array" },
      { id: "labels", type: %w[String Array] },
    ].freeze
    EXPECTED_KEYS = [:title, :body, :labels]

    sig { returns(T.untyped) }
    def body
      Array(@body)
    end

    sig { returns(T.untyped) }
    def labels
      Array(@labels)
    end

    private

    def build
      @raw_data = YAML.safe_load(@input)

      unless @raw_data.is_a?(Hash)
        errors.add :base, "Config must contain at least one key", docs: StructuredTemplates::ConfigurationBase::DOCS_URL
        return
      end

      @title = @raw_data.dig("title")
      @body = @raw_data.dig("body")
      @labels = @raw_data.dig("labels")
    rescue Psych::BadAlias, Psych::DisallowedClass, Psych::SyntaxError => e
      # todo: cast into the errors we want to surface
      errors.add :base, ("YAML syntax error: " + e.message), docs: StructuredTemplates::ConfigurationBase::DOCS_URL
    end

    def required_keys
      []
    end

    def optional_keys
      OPTIONAL_KEYS
    end

    def expected_keys
      EXPECTED_KEYS
    end
  end
end
