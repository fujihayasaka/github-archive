# typed: strict
# frozen_string_literal: true

module Settings
  module AccessibilityPreferences
    class KeyboardShortcutsForm < ApplicationForm
      sig do
        params(
          all_shortcuts_enabled: T::Boolean
        ).void
      end
      def initialize(
        all_shortcuts_enabled: T.let(false, T::Boolean)
      )
        @all_shortcuts_enabled = all_shortcuts_enabled
      end

      sig { returns(T::Boolean) }
      attr_reader :all_shortcuts_enabled

      form do |this_form|
        T.bind(self, KeyboardShortcutsForm)

        this_form.check_box(
          name: :keyboard_shortcuts_preference,
          value: "all",
          unchecked_value: "no_character_key",
          label: "Character keys",
          checked: all_shortcuts_enabled
        )

        this_form.submit(name: :submit, label: "Save keyboard shortcut preferences", mt: 2)
      end
    end
  end
end
