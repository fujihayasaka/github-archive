# typed: true
# frozen_string_literal: true

require "psych"

module GitHub::Goomba
  class UISchemaFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("pre[lang='embed']")
    YAML_ERROR = "The above code block contains invalid YAML."

    def self.feature_flags
      [:adaptive_card_markdown_parsing]
    end

    def self.enabled?(context)
      # When considering repos, only consider if the repo is enabled.
      # If there is no repos, check any orgs.
      # Otherwise, it is not enabled
      if context[:entity].is_a?(Repository)
        return context[:entity].try(:adaptive_card_parsing_enabled?)
      elsif context[:organization].is_a?(Organization)
        return context[:organization].try(:adaptive_card_parsing_enabled?)
      end

      false
    end

    def selector
      SELECTOR
    end

    def call(node)
      yaml_str = node.children.first.inner_html
      return node if yaml_str.blank?

      yaml = nil
      errors = []
      deprecation_warnings = []

      begin
        yaml = YAML.safe_load(yaml_str)

        validator = UI::FormSchema::Validator.new(yaml, base_key: "embed")
        validator.validate!
        deprecation_warnings = validator.deprecation_warnings.full_messages
        errors = validator.errors.full_messages
      rescue Psych::BadAlias, Psych::DisallowedClass, Psych::SyntaxError
        errors << YAML_ERROR
      end

      if errors.any?
        node.to_html + render_errors(errors, deprecation_warnings)
      else
        ui = UI::FormSchema.new(yaml, "ui-schema", data_context: data_context.data).call
        ApplicationController.render(ui, formats: [:html], layout: false)
      end
    end

    private

    def data_context
      @data_context ||= UI::DataContext.new(context)
    end

    def render_errors(errors, deprecation_warnings)
      ApplicationController.render(
        UI::ErrorsComponent.new(errors, deprecation_warnings),
        formats: [:html],
        layout: false,
      )
    end
  end
end
