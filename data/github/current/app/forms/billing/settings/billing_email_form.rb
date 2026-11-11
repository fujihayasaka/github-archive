# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class BillingEmailForm < ApplicationForm
      form do |billing_email_form|
        T.bind(self, BillingEmailForm)

        billing_email_form.text_field(
          name: :billing_email,
          label: label,
          hint: hint,
          validation_message: error,
          disabled: disabled,
          required: true,
          data: data.merge(@view_context.test_selector_hash(test_selector)),
          auto_check_src: @view_context.organization_check_billing_email_path
        )
      end

      attr_reader :target, :form, :label, :hint, :error, :disabled, :test_selector, :data

      def initialize(target:, label: "Billing email", hint: "", error: nil, data: {}, disabled: false, test_selector: "")
        @target = target
        @label = label
        @hint = hint
        @error = error
        @disabled = disabled
        @data = data
        @test_selector = test_selector
      end

      def render?
        target.organization? || target.business?
      end
    end
  end
end
