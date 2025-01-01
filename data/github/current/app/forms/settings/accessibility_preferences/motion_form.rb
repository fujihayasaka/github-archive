# typed: strict
# frozen_string_literal: true

module Settings
  module AccessibilityPreferences
    class MotionForm < ApplicationForm
      sig do
        params(current_user: User).void
      end
      def initialize(current_user:)
        @current_user = current_user
      end

      sig { returns(User) }
      attr_reader :current_user

      form do |this_form|
        T.bind(self, MotionForm)

        this_form.radio_button_group(
          name: :animated_images,
          "aria-labelledby": "animated_images_label"
        ) do |radio_group|
          radio_group.radio_button(
            value: "system",
            label: "Sync with system",
            caption: "Adopts your system preference for reduced motion",
            checked: current_user.settings.get(:animated_images) == "system"
          )
          radio_group.radio_button(
            value: "enabled",
            label: "Enabled",
            caption: "Automatically plays animated images",
            checked: current_user.settings.get(:animated_images) == "enabled"
          )
          radio_group.radio_button(
            value: "disabled",
            label: "Disabled",
            caption: "Prevents animated images from playing automatically",
            checked: current_user.settings.get(:animated_images) == "disabled"
          )
        end

        this_form.submit(name: :submit, label: "Save motion preferences", mt: 2)
      end
    end
  end
end
