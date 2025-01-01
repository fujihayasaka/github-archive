# typed: true
# frozen_string_literal: true

module Signups
  class SignupFormFieldsComponent < ApplicationComponent
    attr_reader :form

    sig { params(form: ActionView::Helpers::FormBuilder).void }
    def initialize(form:)
      @form = form
    end
  end
end
