# typed: strict
# frozen_string_literal: true

module Settings
  module AccessibilityPreferences
    class CommandPaletteForm < ApplicationForm
      sig do
        params(
          current_user: User,
          command_mode_options: T::Array[T.untyped],
          search_mode_options: T::Array[T.untyped]
        ).void
      end
      def initialize(
        current_user:,
        command_mode_options: [],
        search_mode_options: []
      )
        @current_user = current_user
        @command_mode_options = command_mode_options
        @search_mode_options = search_mode_options
      end

      sig { returns(T::Array[T.untyped]) }
      attr_reader :command_mode_options

      sig { returns(T::Array[T.untyped]) }
      attr_reader :search_mode_options

      sig { returns(User) }
      attr_reader :current_user

      form do |this_form|
        T.bind(self, CommandPaletteForm)

        this_form.group(layout: :horizontal) do |group|
          group.select_list(
            name: :search_mode_shortcut,
            label: "Search mode"
          ) do |mode_list|
            search_mode_options.each do |label, value|
              mode_list.option(
                label:, value:, selected: current_user.settings.get(:command_palette_open_hotkey) == value
              )
            end
          end

          group.select_list(
            name: :command_mode_shortcut,
            label: "Command mode",
          ) do |mode_list|
            command_mode_options.each do |label, value|
              mode_list.option(
                label:, value:, selected: current_user.settings.get(:command_palette_open_command_mode_hotkey) == value
              )
            end
          end
        end

        this_form.submit(name: :submit, label: "Save command palette preferences", mt: 2)
      end
    end
  end
end
