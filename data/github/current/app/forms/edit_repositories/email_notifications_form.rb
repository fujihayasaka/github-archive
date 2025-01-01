# typed: true
# frozen_string_literal: true

module EditRepositories
  class EmailNotificationsForm < ApplicationForm
    form do |notif_form|
      notif_form.fields_for(:config_attributes) do |builder|
        EmailNotificationsConfigForm.new(
          builder, hook: @hook
        )
      end

      notif_form.check_box(
        name: :active,
        label: "Active",
        caption: GitHub::HTMLSafeString.make(<<~CAPTION)
          We will send notification emails to the listed addresses when a <code>push</code> event is triggered.
        CAPTION
      )

      notif_form.submit(
        name: :submit, label: @hook.new_record? ? "Setup notifications" : "Update settings"
      )
    end

    def initialize(hook:)
      @hook = hook
    end
  end
end
