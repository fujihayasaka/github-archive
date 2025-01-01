# typed: true
# frozen_string_literal: true

class SlashCommands::SelectionControlComponent < ApplicationComponent
  attr_reader :name, :label, :value, :multiple, :description, :error_message, :required, :selected

  def initialize(name, value:, label:, form: nil, required: false, multiple: false, description: nil, error_message: nil, selected: nil)
    @form = form
    @name = name
    @label = label
    @value = value
    @description = description
    @error_message = error_message
    @multiple = multiple
    @required = required
    @selected = selected
  end

  memoize def description_id
    if description.present?
      SecureRandom.hex(3)
    end
  end

  memoize def input_id
    SecureRandom.hex(3)
  end

  memoize def label_id
    SecureRandom.hex(3)
  end

  def params
    params = { required: required, id: input_id }
    params[:"aria-describedby"] = description_id if description_id
    params[:"aria-labelledby"] = label_id if label_id
    params[:checked] = selected
    params[:multiple] = multiple
    params[:required] = required
    params.compact
  end

  def form
    @form || null_form_builder
  end

  def null_form_builder
    instantiate_builder(nil, nil, { class: nil, style: nil, allow_method_names_outside_object: true, skip_default_ids: true })
  end
end
