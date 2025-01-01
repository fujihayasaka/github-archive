# typed: true
# frozen_string_literal: true

module UI
  class FormSchema
    include ActionView::Helpers::TagHelper

    Version = "v1.0"

    attr_reader :validator, :base_name
    delegate :valid?, :deprecation_warnings, :errors, to: :validator

    def initialize(schema, base_name, data_context: {})
      @schema = schema
      @base_name = base_name
      @validator = Validator.new(schema)
      @data_context = data_context
    end

    def call
      unless @validator.valid?
        return UI::ErrorsComponent.new(
          errors.full_messages,
          deprecation_warnings.full_messages,
          mt: 0,
          mb: 3
        )
      end

      rendered_elements = []

      if @validator.deprecation_warnings.any?
        rendered_elements << [UI::ErrorsComponent.new(
          errors.full_messages,
          deprecation_warnings.full_messages,
          mt: 0,
          mb: 3
        )]
      end

      rendered_elements << @schema.map do |element|
        element = element.deep_stringify_keys

        case element["type"]
        when "input" then input_element(element)
        when "textarea" then textarea_element(element)
        when "dropdown" then dropdown_element(element)
        when "checkboxes" then checkboxes_element(element)
        when "markdown" then text_element(element)
        end
      end

      UI.stack(rendered_elements)
    end

    def input_element(element)
      attributes = element["attributes"]

      format = attributes["format"]

      UI.text_field(
        element_name(attributes),
        description: attributes["description"],
        label: attributes["label"],
        placeholder: attributes["placeholder"],
        value: attributes["value"],
        type: format || "text",
        required: element.dig("validations", "required"),
      )
    end

    def textarea_element(element)
      attributes = element["attributes"]

      UI.text_area(
        element_name(attributes),
        description: attributes["description"],
        label: attributes["label"],
        value: attributes["value"],
        placeholder: attributes["placeholder"],
        required: element.dig("validations", "required"),
        markdown_toolbar: true,
      )
    end

    def dropdown_element(element)
      attributes = element["attributes"]

      UI.select(
        element_name(attributes),
        description: attributes["description"],
        items: attributes["options"],
        label: attributes["label"],
        placeholder: attributes["placeholder"],
        required: element.dig("validations", "required"),
        multiple: attributes["multiple"],
        value: attributes["value"]
      )
    end

    def checkboxes_element(element)
      attributes = element["attributes"]

      UI.checkboxes(
        element_name(attributes),
        description: attributes["description"],
        items: attributes["options"],
        value: attributes["value"],
        label: attributes["label"],
        required: element.dig("validations", "required")
      )
    end

    def text_element(element)
      text = GitHub::Goomba::MarkdownPipeline.to_html(element["attributes"]["text"] || element["attributes"]["value"])
      Primer::Beta::Text.new(tag: :div, classes: "markdown-body").with_content(text)
    end

    def validate_text(key, element)
      attribute_key = "#{key}.attributes"
      attributes = element["attributes"]

      if attributes["text"].blank?
        errors.add(attribute_key, "was expected to have a text")
      elsif !attributes["text"].is_a?(String)
        errors.add("#{attribute_key}.text", "was expected to be a String")
      end
    end

    def element_name(attributes)
      name = attributes["id"] || attributes["label"]

      if base_name
        "#{base_name}[#{name}]"
      else
        name
      end
    end
  end
end
