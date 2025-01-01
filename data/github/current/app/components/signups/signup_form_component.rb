# typed: true
# frozen_string_literal: true

module Signups
  class SignupFormComponent < ApplicationComponent
    attr_reader :captcha_demo, :octocaptcha, :show_captcha, :user

    sig do
      params(
        captcha_demo: T::Boolean,
        show_captcha: T::Boolean,
        octocaptcha: Octocaptcha,
        user: User,
        octocaptcha_timeout: T.nilable(Integer)
      ).void
    end
    def initialize(captcha_demo:, show_captcha:, octocaptcha:, user:, octocaptcha_timeout: nil)
      @captcha_demo = captcha_demo
      @octocaptcha = octocaptcha
      @show_captcha = show_captcha
      @user = user
      @octocaptcha_timeout = octocaptcha_timeout
    end

    sig { returns(T::Boolean) }
    def dynamically_load_captcha
      show_captcha && octocaptcha.is_more_data_exchange_enabled.call
    end

    sig { returns(Integer) }
    def octocaptcha_timeout
      @octocaptcha_timeout || Octocaptcha::HIGHER_BROWSER_LOAD_TIMEOUT
    end
  end
end
