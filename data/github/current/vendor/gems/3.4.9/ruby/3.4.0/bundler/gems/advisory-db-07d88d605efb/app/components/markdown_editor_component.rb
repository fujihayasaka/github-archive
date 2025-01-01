# frozen_string_literal: true

require "securerandom"

class MarkdownEditorComponent < ApplicationComponent
  attr_reader :form, :attribute, :toolbar, :px, :text_area_classes, :text_area_data

  def initialize(attribute:, form: nil, id_prefix: nil, disabled: false, required: false, toolbar: true, px: 2, text_area_classes: "", text_area_data: {})
    @attribute = attribute
    @form = form
    @id_prefix = id_prefix
    @disabled = disabled
    @required = required
    @toolbar = toolbar
    @px = px
    @text_area_classes = text_area_classes
    @text_area_data = text_area_data
  end

  def id_prefix
    @id_prefix ? "#{@id_prefix}-" : ""
  end

  def object
    form&.object
  end

  def content
    object&.public_send(attribute)
  end

  def placeholder
    @placeholder ||= "Write a #{attribute}"
  end

  def required?
    @required
  end

  def text_area_id
    @text_area_id ||= if form
                        form.field_id(attribute)
                      else
                        "markdown-textarea-#{component_id}"
                      end
  end

  # This function gives each markdown component a unique ID so that when
  # rendering the preview, it knows which editor to render the preview to
  def component_id
    @component_id ||= SecureRandom.hex(4)
  end
end
