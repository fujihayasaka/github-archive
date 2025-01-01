# typed: true
# frozen_string_literal: true

module SlashCommands
  class SelectComponent < InputComponent
    attr_reader :items, :multiple
    def initialize(name, items:, label: nil, placeholder: nil, description: nil, multiple: false, required: false, value: nil)
      super(name, label: label, placeholder: placeholder, required: required, description: description)

      @multiple = multiple
      @items = Item.wrap(items)
      @value = value
    end

    def render_input
      form.select(
        name,
        options,
        { prompt: placeholder, selected: value }.compact,
        id: input_id,
        multiple: multiple,
        required: required,
        class: "form-select",
        **params
      )
    end

    def options
      items.map do |item|
        [item.text, item.value]
      end
    end
  end
end
