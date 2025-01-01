# typed: strict
# frozen_string_literal: true

module Settings
  module AccessibilityPreferences
    class UnderlinesForm < ApplicationForm
      sig do
        params(current_user: User).void
      end
      def initialize(current_user:)
        @current_user = current_user
      end

      sig { returns(User) }
      attr_reader :current_user

      form do |this_form|
        T.bind(self, UnderlinesForm)

        this_form.radio_button_group(
          name: :link_underlines,
          "aria-labelledby": "link_underline_label"
        ) do |radio_group|
          radio_group.radio_button(
            value: "false",
            label: "Hide link underlines",
            checked: current_user.settings.get(:link_underlines) == false
          )
          radio_group.radio_button(
            value: "true",
            label: "Show link underlines",
            checked: current_user.settings.get(:link_underlines) == true
          )
        end

        this_form.submit(name: :submit, label: "Save content preferences", mt: 2)
      end
    end
  end
end
