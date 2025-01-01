# typed: true
# frozen_string_literal: true

module StructuredTemplates
  class BodyBuilder
    attr_reader :template, :form_params, :templatable
    BLANK_RESPONSE_PLACEHOLDER = "_No response_"

    # template    - An IssueTemplate|DiscussionTemplate.
    # form_params - A Hash of template form parameters.
    # templatable - An Issue|Discussion.
    def initialize(template:, form_params:, templatable: nil)
      @template    = template
      @form_params = form_params || {}
      @templatable = templatable
    end

    def to_markdown
      output = template.user_inputs.map do |input|
        "### #{input.label}" +
        "\n\n" +

        if input.type == "checkboxes"
          convert_checkbox_input_to_md(input)
        else
          convert_input_to_md(input)
        end
      end.join("\n\n")

      output
    end

    def valid?
      validate_presence_of_required_fields
      templatable.errors.empty?
    end

    private

    def convert_input_to_md(input)
      answer = form_params.dig(input.id).presence || BLANK_RESPONSE_PLACEHOLDER

      if render_codeblock?(input, answer)
        <<~MARKDOWN
          ```#{input.render}
          #{clean_codeblock(answer)}
          ```
        MARKDOWN
      else
        "#{answer_to_string(answer)}"
      end
    end

    # checkboxes have a different structure than other inputs so must be handled differently
    def convert_checkbox_input_to_md(input)
      input.checkboxes.map do |checkbox|
        if form_params.dig(input.id, checkbox.id).presence
          "- [X] #{checkbox.label}"
        else
          "- [ ] #{checkbox.label}"
        end
      end.join("\n")
    end

    def answer_to_string(answer)
      return answer if answer.is_a?(String)

      if answer.is_a?(Array)
        answer.join(", ")
      end
    end

    def clean_codeblock(answer)
      answer.sub(/(```)(\w+)/, "").sub(/(```)/, "").strip
    end

    def render_codeblock?(input, answer)
      input.type == "textarea" && input.render.present? && answer != BLANK_RESPONSE_PLACEHOLDER
    end

    def validate_presence_of_required_fields
      template.inputs.select(&:required).each do |required_input|
        if form_params.dig(required_input.id).blank?
          templatable.errors.add "'#{required_input.label}'", "is required"
        end
      end
    end
  end
end
