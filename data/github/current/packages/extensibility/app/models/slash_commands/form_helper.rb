# typed: false
# frozen_string_literal: true

module SlashCommands
  module FormHelper
    # Display dropdown menu that can be controlled with the keyboard. Useful when
    # asking a user to pick one of a few options.
    #
    # ==== Options
    #
    # - `items`: An array of `SlashCommand:Item`s to include in the menu. Required.
    # - `blankslate_title`: Text to display as title in blankslate when items is an empty array. Defaults to "Not found".
    # - `blankslate_description`: Text to display in blankslate when items is an empty array.
    #
    # ==== Examples
    #
    #    menu(:employee_type, [Item.from("Full-time"), Item.from("Part-time"), Item.from("Contract")])
    #    menu(:replies, [Item.from("Some reply")], blankslate_title: "No saved replies", blankslate_description: "Add a new saved reply.")
    def menu(name, items:, blankslate_title: "Not found", blankslate_description: nil)
      if items.present?
        SlashCommands::MenuComponent.new(
          command: self,
          items: items,
          next_page: next_page_number,
          breadcrumbs: breadcrumbs,
          name: name
        )
      else
        blankslate(blankslate_title, description: blankslate_description)
      end
    end

    # Display a blankslate dialog near over the cursor. Useful when there are no
    # options to display to the user.
    #
    # ==== Examples
    #
    #    blankslate("No saved replies", description: "You can create one in your settings")
    def blankslate(title, description:)
      SlashCommands::BlankslateComponent.new(title: title, description: description, breadcrumbs: breadcrumbs)
    end

    # Wraps provided components in a slash command form.
    #
    # Caveat: This method relies on the precence of a
    #         SlashCommands::Page defined in a local scope.
    #
    # ==== Options
    #
    # - `pt`: set top padding for form using Primer padding values.
    #
    # ==== Examples
    #
    #    form(
    #      text_field(:name),
    #      text_field(:email),
    #      text_area(:message)
    #    )
    #    form(text_field(:message)).with_actions(
    #      "some text",
    #      close_button("Quit"),
    #      submit_button("Send the form")
    #    )
    def form(*fields, pt: 0, submit_action: UI.submit_button, close_action: UI.close_button)
      case page&.form_style
      when nil, :embedded
        SlashCommands::EmbeddedFormComponent.new(
          command: self,
          fields: fields,
          pt: pt,
          actions: [close_action, submit_action]
        )
      when :dialog
        SlashCommands::DialogFormComponent.new(
          command: self,
          fields: fields,
          pt: pt,
          actions: [submit_action]
        )
      when :modal
        SlashCommands::ModalFormComponent.new(
          command: self,
          fields: fields,
          pt: pt,
          actions: [close_action, submit_action]
        )
      end
    end
  end
end
