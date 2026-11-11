# typed: strict
# frozen_string_literal: true

module Signups
  class MarketingConsentFieldsComponent < ApplicationComponent
    sig { params(actor_country_code: T.nilable(String), show_copilot_opt_in: T::Boolean).void }
    def initialize(actor_country_code:, show_copilot_opt_in: false)
      @actor_country_code = actor_country_code
      @show_copilot_opt_in = show_copilot_opt_in
    end

    private

    sig { returns(T.nilable(String)) }
    attr_reader :actor_country_code

    sig { returns(T::Boolean) }
    attr_reader :show_copilot_opt_in

    sig { returns(ActionView::Helpers::FormBuilder) }
    def user_signup_form_builder
      ActionView::Helpers::FormBuilder.new(:user_signup, nil, self, {})
    end

    sig { returns(T::Array[T::Array[String]]) }
    def countries
      ::TradeControls::Countries.currently_unsanctioned
    end
  end
end
