# typed: true
# frozen_string_literal: true

class SlashCommands::TextFieldComponent < SlashCommands::InputComponent
  attr_reader :type

  VALID_TYPES = %w(
    color
    date
    datetime-local
    email
    month
    number
    password
    range
    tel
    text
    time
    url
    week
  )

  def initialize(name, label: nil, value: nil, placeholder: nil, description: nil, type: "text", required: false)
    super(name, label: label, value: value, placeholder: placeholder, description: description, required: required)
    @type = fetch_or_fallback(VALID_TYPES, type || "text", "text")
  end

  def render_input
    form.text_field(
      name,
      value: value,
      type: type,
      id: input_id,
      placeholder: placeholder,
      class: "form-control input-block",
      required: required,
      **params
    )
  end

  def placeholder
    return if super == false

    super || label_text || default_label_text
  end
end
