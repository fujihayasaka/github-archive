# typed: false
# frozen_string_literal: true

module EditRepositories
  class EmailNotificationsConfigForm < ApplicationForm
    form do |config_form|
      config_form.hidden(
        name: :send_from_author,
        value: @hook.config["send_from_author"].present? ? @hook.config["send_from_author"] : "0"
      )

      config_form.text_field(
        name: :address,
        label: "Address",
        value: @hook.config["address"],
        placeholder: "one@example.com two@example.com",
        required: true,
        validation_message: find_validation_message_for(:address),
        caption: "Whitespace separated email addresses (at most two)."
      )

      config_form.text_field(
        name: :secret,
        label: "Approved header",
        value: @hook.config["secret"],
        validation_message: find_validation_message_for(:secret),
        caption: GitHub::HTMLSafeString.make(<<~CAPTION)
          Sets the <code>Approved</code> header to automatically approve the
          message in a read-only or moderated mailing list.
        CAPTION
      )
    end

    def initialize(hook:)
      @hook = hook
    end

    private

    def find_validation_message_for(field)
      @hook.errors.each do |hook_error|
        if hook_error.options[:config_attribute] == field
          return hook_error.options[:message]
        end
      end

      nil
    end
  end
end
