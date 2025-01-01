# typed: strict
# frozen_string_literal: true

module Settings
  module AccessibilityPreferences
    class HovercardsForm < ApplicationForm
      sig do
        params(current_user: User, is_mac: T::Boolean).void
      end
      def initialize(current_user:, is_mac:)
        @current_user = current_user
        @is_mac = is_mac
      end

      sig { returns(User) }
      attr_reader :current_user

      sig { returns(T::Boolean) }
      attr_reader :is_mac

      sig { returns(String) }
      def operator_key
        is_mac ? "⌥" : "Alt"
      end

      sig { returns(String) }
      def sr_text
        (is_mac ? "option" : "alt") + " up"
      end

      form do |this_form|
        T.bind(self, HovercardsForm)

        this_form.check_box(
          name: :hovercards_enabled,
          value: "all",
          unchecked_value: "",
          label: "Hovercards",
          checked: current_user.settings.get(:hovercards_enabled)
        )

        this_form.submit(name: :submit, label: "Save hovercard preferences", mt: 2)
      end
    end
  end
end
