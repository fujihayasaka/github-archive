# typed: true
# frozen_string_literal: true

module SlashCommands
  class SelectionControlGroupComponent < SlashCommands::InputComponent
    attr_reader :items, :defaults, :value

    # Creates a list of checkboxes using given name.
    #
    # ==== Options
    # * <tt>:items</tt> - A list of SlashCommand::Item objects that are used to draw form elements.
    # * <tt>:label</tt> - The label displayed above the inputs. Defaults to `false`.
    # * <tt>:form</tt> - The form builder, optional.
    #
    # ==== Examples
    #
    #    SelectionControlGroupComponent.new(:my_field, items: [Item.new(...)])
    #    SelectionControlGroupComponent.new(:my_field, items: [Item.new(...)], label: "Pick one")
    #    SelectionControlGroupComponent.new(:my_field, items: [Item.new(...)])
    def initialize(name, items:, description: nil, required: false, label: false, value: nil)
      super(name, label: label, placeholder: nil, description: description, required: required)

      @items = Item.wrap(items)
      @value = value
    end

    def form_group_body_described?
      true
    end

    def render_input
      items.each do |item|
        selected = Array.wrap(value).compact.include?(item.value).presence
        component = SelectionControlComponent.new(
          name,
          form: form,
          value: item.value,
          label: item.text,
          description: item.description,
          required: required,
          multiple: items.count > 1,
          error_message: item_for_errors == item ? error_message : nil,
          selected: selected
        )

        concat(render(component))
      end

      nil
    end

    # Return the item to which error messages should be attached.
    def item_for_errors
      first_checked_item = items.find do |item|
        item.value == value
      end

      first_checked_item || items.last
    end

    # Delegate error handling to selection control component
    def errors?
      false
    end
  end
end
