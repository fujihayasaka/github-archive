# typed: strict
# frozen_string_literal: true

module Settings
  module AccessibilityPreferences
    class PastingForm < ApplicationForm
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

      form do |this_form|
        T.bind(self, PastingForm)

        this_form.radio_button_group(
          name: :paste_url_markdown,
          "aria-labelledby": "url_pasting_label"
        ) do |radio_group|
          radio_group.radio_button(
            value: "true",
            label: "Formatted link",
            caption: "Pasting a URL while having text selected will format to a Markdown link",
            checked: current_user.settings.get(:paste_url_markdown)
          )
          radio_group.radio_button(
            value: "false",
            label: "Plain text",
            caption: "Pasting a URL while having text selected will replace the text",
            checked: !current_user.settings.get(:paste_url_markdown)
          )
        end

        this_form.submit(name: :submit, label: "Save editor settings", mt: 2)
      end
    end
  end
end
