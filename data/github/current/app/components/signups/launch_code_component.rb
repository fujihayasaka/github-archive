# typed: true
# frozen_string_literal: true

module Signups
  class LaunchCodeComponent < ApplicationComponent
    attr_reader :email,
                :resent,
                :launch_code_length,
                :error,
                :resend_verification_path,
                :update_email_path,
                :hidden_fields_params,
                :dark_mode

    sig do params(
      email: UserEmail,
      show_launch_code: T::Boolean,
      resent: T::Boolean,
      launch_code_length: Integer,
      error: T.nilable(String),
      resend_verification_path: String,
      update_email_path: String,
      hidden_fields_params: T::Hash[Symbol, T.untyped],
      dark_mode: T::Boolean
    ).void
    end
    def initialize(
      email:,
      show_launch_code:,
      resent:,
      launch_code_length:,
      error:,
      resend_verification_path:,
      update_email_path:,
      hidden_fields_params:,
      dark_mode: false
    )
      @email = email
      @show_launch_code = show_launch_code
      @resent = resent
      @launch_code_length = launch_code_length
      @error = error
      @resend_verification_path = resend_verification_path
      @update_email_path = update_email_path
      @hidden_fields_params = hidden_fields_params
      @dark_mode = dark_mode
    end

    private

    def color_theme
      @dark_mode ? "dark" : "light"
    end

    def show_launch_code?
      @show_launch_code
    end
  end
end
