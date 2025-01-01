# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class VatCodeForm < ApplicationForm
      form do |vat_code_form|
        T.bind(self, VatCodeForm)

        vat_code_form.text_field(
          name: :vat_code,
          label: "VAT/GST ID",
          value: value,
          required: required,
          maxlength: 50,
          disabled: disabled,
          autocomplete: "off",
          data: { test_selector: test_selector },
          **form_attributes
        )
      end

      attr_reader :required, :disabled, :form_attributes, :test_selector, :value

      def initialize(required: false, disabled: false, form_attributes: {}, test_selector: "vat-code", value: nil)
        @required = required
        @disabled = disabled
        @form_attributes = form_attributes
        @test_selector = test_selector
        @value = value
      end
    end
  end
end
