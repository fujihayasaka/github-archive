# typed: true
# frozen_string_literal: true

class SlashCommands::InputComponent < ApplicationComponent
  attr_writer :form
  attr_reader :name, :label_text, :placeholder, :required, :description

  def initialize(name, label: nil, value: nil, placeholder: nil, description: nil, required: false)
    @name = name
    @label_text = label.present? ? label : default_label_text
    # You can hide the label by setting it to false.
    @show_label = (label.nil? || label.present?)
    @placeholder = placeholder
    @required = required
    @value = value
    @description = description
  end

  def description_id
    return nil if description.blank?
    @description_id ||= SecureRandom.hex(3)
  end

  def label_id
    return nil unless label?
    @label_id ||= SecureRandom.hex(3)
  end

  memoize def input_id
    [
      form.object_name,
      name.to_s
    ].compact.join("_").gsub(/[^a-zA-Z0-9_-]/, "_")
  end

  def params
    params = {}
    params[:"aria-describedby"] = description_id if description_id
    params[:"aria-labelledby"] = label_id if label_id
    params
  end

  def form
    @form || null_form_builder
  end

  memoize def null_form_builder
    instantiate_builder(nil, nil, { class: nil, style: nil, allow_method_names_outside_object: true, skip_default_ids: true })
  end

  # Most inputs are described, however checkboxes and radio buttons are grouped. So those groups are described instead.
  # This happens at this level, so we override this to be true where needed
  def form_group_body_described?
    false
  end

  # When label false, don't show.
  def label?
    @show_label
  end

  def default_label_text
    name.to_s.humanize
  end

  def value
    return @value if @value
    return unless form.object && form.object.respond_to?(name)
    form.object.public_send(name)
  end

  def errors?
    return unless form.object

    form.object.errors.key?(name)
  end

  def border?
    false
  end

  def error_message
    return unless form.object

    form.object.errors.full_messages_for(name).to_sentence
  end

  def render_input
    raise NotImplementedError, <<~ERROR
      You need to implement #render_input in your InputComponent subclass.

      This method should return an HTML safe string containing the input tag.
      Don't worry about rendering labels or errors; those are handled for you.
    ERROR
  end
end
