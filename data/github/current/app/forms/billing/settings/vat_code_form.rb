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
          required: required,
          maxlength: 50,
          disabled: disabled,
          autocomplete: "off",
          **form_attributes
        )
      end

      attr_reader :required, :disabled, :form_attributes

      def initialize(required: false, disabled: false, form_attributes: {})
        @required = required
        @disabled = disabled
        @form_attributes = form_attributes
      end
    end
  end
end
