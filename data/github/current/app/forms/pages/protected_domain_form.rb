# typed: strict
# frozen_string_literal: true

module Pages
  class ProtectedDomainForm < ApplicationForm
    sig { params(validation_error: T.nilable(String)).void }
    def initialize(validation_error: nil)
      @validation_error = validation_error
    end

    sig { returns(T.nilable(String)) }
    attr_reader :validation_error

    form do |protected_domain_form|
      T.bind(self, Pages::ProtectedDomainForm)

      protected_domain_form.text_field(
        name: "page_protected_domain[name]",
        label: "What domain would you like to add?",
        required: true,
        validation_message: validation_error,
      )
      protected_domain_form.submit(
        name: :submit,
        label: "Add domain",
        scheme: :primary
      )
    end
  end
end
