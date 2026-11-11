# typed: true
# frozen_string_literal: true

module SlashCommands
  class DemosCommand < ApplicationSlashCommand
    category :unreleased

    trigger_on name: "demos", title: "Demos", description: "See how different things work."

    def self.enabled?(context)
      return super if context.current_user.site_admin?
      return false unless Rails.env.development?

      super
    end

    menu :pick_a_demo
    form :send_message, breadcrumb: "Send message", if: :send_message?
    form :form_actions_demo, breadcrumb: "Form actions", if: :form_actions?
    form :form_actions_demo, style: :dialog, breadcrumb: "Form actions (dialog)", if: :form_actions_dialog?
    form :form_actions_demo, style: :modal, breadcrumb: "Form actions (modal)", if: :form_actions_modal?
    form :selection_controls_demo, breadcrumb: "Checkboxes", if: :selection_controls?, validations: -> (page) {
      page.validates :extras, presence: true
    }
    fill :show_data

    def pick_a_demo
      items = [
        Item.new(text: "Checkboxes", description: "Illustrates checkboxes", value: "selection_controls"),
        Item.new(text: "Form actions", description: "Customize things at the bottom of the form", value: "form_actions"),
        Item.new(text: "Form actions (dialog style)", description: "Customize things at the bottom of the form in a dialog", value: "form_actions_dialog"),
        Item.new(text: "Form actions (modal style)", description: "Customize things at the bottom of the form in a modal", value: "form_actions_modal"),
        Item.new(text: "Send a message", description: "Show off UI forms", value: "send_message"),
      ]

      menu(:demo, items: items)
    end

    def form_actions_demo
      form(
        UI.columns(
          UI.text_field(:first),
          UI.text_field(:middle),
          UI.text_field(:last),
        ),
        UI.text_area(:content)
      ).with_actions(
        UI.close_button("Cancel"),
        UI.submit_button("Insert data")
      )
    end

    def send_message
      priorities = [
        Item.new(value: "Urgent"),
        Item.new(value: "Important"),
        Item.new(value: "Later is fine"),
      ]

      form(
        UI.text_field(:to),
        UI.text_field(:cc),
        UI.text_field(:subject),
        UI.select(:priority, items: priorities),
        UI.text_area(:body),
      ).with_actions(
        UI.submit_button("Send message")
      )
    end

    def selection_controls_demo
      data[:super_size] = true                   unless data.key?(:super_size)
      data[:extras]     = %w[Ketchup Vinegar] unless data.key?(:extras)

      kind = [
        Item.new(value: "Hamburger"),
        Item.new(value: "Cheeseburger"),
        Item.new(value: "Chicken McNuggets"),
      ]

      extras = [
        Item.new(value: "Ketchup"),
        Item.new(value: "Vinegar"),
        Item.new(value: "McChicken Sauce", description: "$0.20 per package"),
      ]

      super_size = Item.new(text: "Super size", value: "super_size", description: "Large drink and extra large toy.")

      form(
        UI.select(:status, items: kind),
        UI.checkbox(:super_size, super_size),
        UI.text_area(:special_instructions),
        UI.checkboxes(:extras, items: extras, label: "Extras")
      )
    end

    def show_data
      data
    end

    def selection_controls?
      data[:demo] == "selection_controls"
    end

    def form_actions?
      data[:demo] == "form_actions"
    end

    def form_actions_dialog?
      data[:demo] == "form_actions_dialog"
    end

    def form_actions_modal?
      data[:demo] == "form_actions_modal"
    end

    def send_message?
      data[:demo] == "send_message"
    end
  end
end
