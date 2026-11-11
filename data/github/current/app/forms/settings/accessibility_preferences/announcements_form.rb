# typed: strict
# frozen_string_literal: true

module Settings
  module AccessibilityPreferences
    class AnnouncementsForm < ApplicationForm
      sig do
        params(current_user: User).void
      end
      def initialize(current_user:)
        @current_user = current_user
      end

      sig { returns(User) }
      attr_reader :current_user

      form do |this_form|
        T.bind(self, AnnouncementsForm)

        this_form.radio_button_group(
          name: :announcement_preference_hovercard,
        ) do |radio_group|
          radio_group.radio_button(
            value: "true",
            label: "Enable screen reader hint",
            checked: current_user.settings.get(:announcement_preference_hovercard)
          )
          radio_group.radio_button(
            value: "false",
            label: "Disable screen reader hint",
            checked: !current_user.settings.get(:announcement_preference_hovercard)
          )
        end

        this_form.submit(name: :submit, label: "Save assistive technology hint preferences", mt: 2)
      end
    end
  end
end
