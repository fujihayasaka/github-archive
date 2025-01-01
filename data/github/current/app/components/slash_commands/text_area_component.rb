# typed: true
# frozen_string_literal: true

module SlashCommands
  class TextAreaComponent < InputComponent

    attr_reader :markdown_toolbar
    def initialize(name, label: false, value: nil, placeholder: nil, description: nil, markdown_toolbar: true, required: false)
      super(name, label: label, value: value, placeholder: placeholder, description: description, required: required)

      @markdown_toolbar = markdown_toolbar
    end

    def render_input
      if markdown_toolbar
        render Comments::PreviewableCommentFormComponent.new(
          textarea_id: input_id,
          current_repository: helpers.current_repository,
          field_name: input_name,
          body: value,
          required: required,
          placeholder: placeholder,
          subject: IssueComment.new,
          use_fixed_width_font: !!current_user&.use_fixed_width_font?,
          aria: {
            describedby: params[:"aria-describedby"],
            labelledby: params[:"aria-labelledby"]
          }
        )
      else
        form.text_area(
          name,
          **params
        )
      end
    end

    def input_name
      if form.object_name
        "#{form.object_name}[#{name}]"
      else
        name
      end
    end

    def border?
      markdown_toolbar
    end

    def params
      super.merge(
        value: value,
        placeholder: placeholder,
        class: "form-control input-block",
        required: required,
        id: input_id,
      )
    end

    def placeholder
      super || label_text || default_label_text
    end
  end
end
