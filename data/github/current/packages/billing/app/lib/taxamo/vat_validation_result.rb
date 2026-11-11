# typed: strict
# frozen_string_literal: true

module Taxamo
  class VatValidationResult < T::Struct
    class InvoiceAddress < T::Struct
      prop :country, T.nilable(String)
      prop :freeform_address, T.nilable(String)
    end

    prop :buyer_tax_number, T.nilable(String)
    prop :buyer_tax_number_valid, T::Boolean, default: false
    prop :buyer_tax_number_format_valid, T::Boolean, default: false
    prop :buyer_tax_number_normalized, T.nilable(String)
    prop :buyer_tax_number_cached, T::Boolean, default: false
    prop :buyer_name, T.nilable(String)
    prop :billing_country_code, T.nilable(String)
    prop :tax_deducted, T::Boolean, default: false
    prop :warnings, T.nilable(T::Array[String])
    prop :invoice_address, T.nilable(InvoiceAddress)

    prop :error, T.nilable(Taxamo::Client::Error)
    prop :request_failed, T::Boolean, default: false
    prop :raw_response, T.nilable(T::Hash[T.untyped, T.untyped]), default: nil
  end
end
