# typed: true
# frozen_string_literal: true

module UI
  extend self

  # Create a form.
  #
  # After creating the form, you can configure it using a few methods:
  # * <tt>with_fields</tt> - Provide an array of components or strings to render into the form body.
  # * <tt>with_actions</tt> - Provide an array of components or strings to render into the form action area.
  # * <tt>with_model</tt> - Provide data using `attributes:` and field scoping using `name:`.
  #
  # ==== Options
  # * <tt>:model</tt> - Provide an ActiveModel::Model instance, such as User.first.
  # * <tt>:url</tt> - Provide a URL for the form. Overrides URL derived from model.
  # * <tt>:method</tt> - Form method used. Defaults to :post.
  # * <tt>**primer_system_arguments</tt> - Learn more at https://primer.style/view-components/system-arguments
  #
  # ==== Examples
  #
  #    UI.form(model: User.first)
  #      .with_fields(UI.text_field(:login))
  #
  #    UI.form(url: search_path, method: :get)
  #      .with_fields(UI.text_field(:q))
  #      .with_actions(UI.submit_button("Search"))
  #
  #    UI.form(url: search_path, method: :get)
  #      .with_fields(UI.text_field(:q))
  #      .with_model(name: "search", attributes: { q: "author:monalisa" })
  #
  #    UI.form(model: User.first, mt: 4, p: 3, data: { foo: :bar })
  def form(model: nil, url: nil, method: nil, **primer_system_arguments)
    FormComponent.new(model: model, url: url, method: method, **primer_system_arguments)
  end

  # Add a select to a form.
  #
  # ==== Options
  # * <tt>:items</tt> - A list of `SlashCommands::Item` instances, used to render options.
  # * <tt>:label</tt> - Defaults to name.
  # * <tt>:placeholder</tt> - Set to a string to add placeholder option.
  # * <tt>:multiple</tt> - Whether to allow the user to select multiple items. Default is false.
  # * <tt>:required</tt> - Mark input as required for browser.
  #
  # ==== Examples
  #
  #    work_types = [SlashCommands::Item.new(value: "Full-time"), SlashCommands::Item.new(value: "Part-time"), ...]
  #    select(:availability, items: work_types)
  #    select(:availability, items: work_types, label: "I'm looking for:")
  #    select(:availability, items: work_types, placeholder: "Choose an option")
  def select(name, items:, label: nil, placeholder: nil, description: nil, multiple: false, required: false, value: nil)
    SlashCommands::SelectComponent.new(
      name,
      items: items,
      label: label,
      placeholder: placeholder,
      description: description,
      multiple: multiple,
      required: required,
      value: value
    )
  end

  # Add a checkbox to a form.
  #
  # ==== Options
  # * <tt>:required</tt> - Mark input as required for browser.
  #
  # ==== Examples
  #
  #    checkbox(:availability, SlashCommands::Item.new(value: "Available"))
  def checkbox(name, item, required: false)
    checkboxes(name, items: [item], required: required)
  end

  # Add checkboxes to a form. Depending on how many items are passed, the data
  # will be available as a string, an array, or nil.
  #
  # * When a single item is passed, the value will be stored as a string.
  # * When more than one item is passed, selected values will be stored in an array.
  # * If none of the items are selected, value will be nil.
  #
  # ==== Options
  # * <tt>:items</tt> - A list of `SlashCommands::Item` instances, used to render checkboxes.
  # * <tt>:label</tt> - Set to a string to display a label above inputs.
  # * <tt>:required</tt> - Mark input as required for browser.
  #
  # ==== Examples
  #
  #    work_types = [SlashCommands::Item.new(value: "Full-time"), SlashCommands::Item.new(value: "Part-time"), ...]
  #    checkboxes(:work_types, items: work_types)
  #    checkboxes(:work_types, items: work_types, label: "I'm interested in:")
  def checkboxes(name, items:, label: false, description: nil, required: false, value: nil)
    SlashCommands::SelectionControlGroupComponent.new(
      name,
      items: items,
      value: value,
      description: description,
      label: label,
      required: required,
    )
  end

  # Add text field to form.
  #
  # ==== Options
  # * <tt>:label</tt> - Set label text to display. By default, uses humanized name.
  # * <tt>:placeholder</tt> - Set input placeholder, set to false to hide. By default, use humanized name.
  # * <tt>:value</tt> - Set the initial value of the text field. By default, nil.
  # * <tt>:type</tt> - Set to change the input type, see SlashCommands::TextFieldComponent::VALID_TYPES for options. Defaults to `text`.
  # * <tt>:required</tt> - Mark input as required for browser.
  #
  # ==== Examples
  #
  #    text_field(:body)
  #    text_field(:body, label: "Message")
  #    text_field(:body, placeholder: "Type something...")
  #    text_field(:body, placeholder: false)
  def text_field(name, label: nil, placeholder: nil, description: nil, value: nil, type: "text", required: false)
    SlashCommands::TextFieldComponent.new(
      name,
      value: value,
      label: label,
      placeholder: placeholder,
      description: description,
      type: type,
      required: required
    )
  end

  # Add text area to form.
  #
  # ==== Options
  # * <tt>:label</tt> - Set label text to display. By default, label isn't shown.
  # * <tt>:placeholder</tt> - Set input placeholder. By default, use humanized name.
  # * <tt>:markdown_toolbar</tt> - Set to false to disable markdown toolbar.
  # * <tt>:required</tt> - Mark input as required for browser.
  #
  # ==== Examples
  #
  #    text_area(:body)
  #    text_area(:body, label: "Message")
  #    text_area(:body, placeholder: "Type something...")
  #    text_area(:body, markdown_toolbar: false)
  def text_area(name, label: false, value: nil, placeholder: nil, description: nil, markdown_toolbar: true, required: false)
    SlashCommands::TextAreaComponent.new(
      name,
      label: label,
      placeholder: placeholder,
      description: description,
      value: value,
      markdown_toolbar: markdown_toolbar,
      required: required,
    )
  end

  def close_button(text = "Cancel", disable_with: text)
    Primer::ButtonComponent.new(data: { close_dialog: true, disable_with: disable_with }).with_content(text) # rubocop:disable Primer/DeprecatedComponents
  end

  def submit_button(text = "Submit", disable_with: text)
    Primer::ButtonComponent.new( # rubocop:disable Primer/DeprecatedComponents
      type: :submit,
      scheme: :primary,
      data: { disable_with: disable_with }
    ).with_content(text)
  end

  # Renders components in column layout. When possible, columns are equally sized.
  #
  # ==== Examples
  #
  #    UI.columns(
  #      UI.text_field(:first),
  #      UI.text_field(:middle),
  #      UI.text_field(:last),
  #    )
  def columns(*components)
    SlashCommands::ColumnsComponent.new(components)
  end

  # Combine components and text into a renderable object. Useful in contexts
  # where you'd like to provide multiple components but can only provide one.
  #
  # ==== Examples
  #
  #     stack(Primer::Link.new(href: "#"), "Some text")
  def stack(*components)
    SlashCommands::StackComponent.new(components)
  end
end
