# typed: true
# frozen_string_literal: true

module StructuredTemplates
  class TemplateComponent < ApplicationComponent
    COMPONENT_TYPE_MAPPING = {
      "markdown" => StructuredTemplates::Elements::MarkdownComponent,
      "dropdown" => StructuredTemplates::Elements::DropdownComponent,
      "input" => StructuredTemplates::Elements::InputComponent,
      "textarea" => StructuredTemplates::Elements::TextareaComponent,
      "multi_select" => StructuredTemplates::Elements::MultiSelectComponent,
      "checkboxes" => StructuredTemplates::Elements::CheckboxComponent,
      "codeblock" => StructuredTemplates::Elements::CodeblockComponent,
    }
    PREFILLABLE_INPUTS = %W(input textarea)

    def initialize(template:, templatable: nil, preview: false)
      @template    = template
      @templatable = templatable
      @preview     = preview
    end

    private

    attr_reader :template, :templatable

    def preview?
      @preview
    end

    memoize def inputs
      inputs = template.inputs.map do |input|
        if prefillable?(input)
          value = templatable.structured_template_inputs[input.id.to_sym]
          input.value = value if value.present?
        end

        component =
          if input.type == "dropdown" && input.multiple?
            component_for("multi_select")
          elsif  input.type == "textarea" && input.codeblock?
            component_for("codeblock")
          else
            component_for(input.type)
          end

        if component
          render component.new(
            element: input,
            preview: preview?,
            templatable: templatable,
            base_form_param: base_form_param,
          )
        end
      end

      safe_join(inputs.compact)
    end

    def render?
      return false unless template.present?

      template.valid?
    end

    def component_for(input_type)
      COMPONENT_TYPE_MAPPING[input_type]
    end

    def prefillable?(input)
      return false unless PREFILLABLE_INPUTS.include? input.type
      templatable.present? && templatable.structured_template_inputs.present?
    end

    def base_form_param
      template.is_a?(DiscussionTemplate) ? :discussion_form : :issue_form
    end

    def slash_commands_surface
      template.is_a?(DiscussionTemplate) ? SlashCommands::DISCUSSION_SURFACE : SlashCommands::ISSUE_BODY_SURFACE
    end
  end
end
