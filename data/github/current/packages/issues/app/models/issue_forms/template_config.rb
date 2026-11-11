# typed: true
# frozen_string_literal: true

module IssueForms
  class TemplateConfig < StructuredTemplates::ConfigurationBase
    attr_reader :name, :title, :type, :body, :assignees, :labels, :projects, :description

    REQUIRED_KEYS = [{ id: "name", type: "String" }].freeze
    OPTIONAL_KEYS = [
      { id: "description", type: "String" },
      { id: "title", type: "String" },
      { id: "type", type: "String" },
      { id: "body", type: "Array" },
      { id: "assignees", type: %w[String Array] },
      { id: "labels", type: %w[String Array] },
      { id: "projects", type: %w[String Array] },
      { id: "memexes", type: "String" },
    ].freeze
    EXPECTED_KEYS = [:name, :description, :title, :body, :assignees, :labels, :memexes, :projects]

    def memexes
      @memexes.split(",").map(&:strip)
    end

    private

    def build
      input = if @input.is_a?(String)
        @input.gsub("\xEF\xBB\xBF".encode("UTF-8"), "")
      else
        @input
      end

      @raw_data = YAML.safe_load(input)

      unless @raw_data.is_a?(Hash)
        errors.add :base, "Config must contain at least one key", docs: StructuredTemplates::ConfigurationBase::DOCS_URL
        return
      end

      @name = @raw_data.dig("name")
      @description = @raw_data.dig("description")
      @about = @raw_data.dig("about")
      @title = @raw_data.dig("title")
      @type = @raw_data.dig("type")
      @body = @raw_data.dig("body")
      @issue_body = true_if_undefined(@raw_data, "issue_body")
      @assignees = @raw_data.dig("assignees")
      @labels = @raw_data.dig("labels")
      @projects = @raw_data.dig("projects")
      @memexes = @raw_data.dig("memexes")
    rescue Psych::BadAlias, Psych::DisallowedClass, Psych::SyntaxError => e
      # todo: cast into the errors we want to surface
      errors.add :base, ("YAML syntax error: " + e.message), docs: StructuredTemplates::ConfigurationBase::DOCS_URL
    end

    def required_keys
      REQUIRED_KEYS
    end

    def optional_keys
      OPTIONAL_KEYS
    end

    def expected_keys
      type_field_enabled ? EXPECTED_KEYS + [:type] : EXPECTED_KEYS
    end
  end
end
