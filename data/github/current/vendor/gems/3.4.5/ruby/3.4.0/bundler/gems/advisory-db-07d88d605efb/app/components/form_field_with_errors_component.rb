# frozen_string_literal: true

class FormFieldWithErrorsComponent < ApplicationComponent
  attr_reader :object, :attribute, :classes, :data, :hidden

  renders_one :label_content

  def initialize(object: nil, attribute: nil, classes: "", data: {}, hidden: false)
    @object = object
    @attribute = attribute
    @classes = classes
    @data = data
    @hidden = hidden
  end

  def error?
    object ? object.errors.include?(attribute) : false
  end

  def form_group_class
    if error?
      "errored #{classes}"
    else
      classes
    end
  end

  def message
    return nil unless error?

    object.errors.full_messages_for(attribute).join(". ").concat(".")
  end
end
