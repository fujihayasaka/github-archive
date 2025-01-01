# typed: true
# frozen_string_literal: true

module Signups
  class MarketingConsentFieldsComponent < ApplicationComponent
    sig { params(actor_country_code: T.nilable(String)).void }
    def initialize(actor_country_code:)
      @actor_country_code = actor_country_code
    end

    private

    sig { returns(T.nilable(String)) }
    attr_reader :actor_country_code

    sig { returns(ActionView::Helpers::FormBuilder) }
    def user_signup_form_builder
      ActionView::Helpers::FormBuilder.new(:user_signup, nil, self, {})
    end
  end
end
