# typed: strict
# frozen_string_literal: true

module Signups
  class TermsOfServiceComponent < ApplicationComponent
    sig { returns(T.nilable(T::Boolean)) }
    def render?
      GitHub.terms_of_service_enabled?
    end
  end
end
