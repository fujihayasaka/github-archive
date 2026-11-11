# typed: true
# frozen_string_literal: true

module Sessions
  module Webauthn
    class RegisterComponent < ApplicationComponent
      include WebauthnHelper

      def initialize(convert_for:, from_settings:, existing_security_key_count: 0, existing_passkey_count: 0)
        @convert_for = convert_for
        @from_settings = from_settings
        @existing_security_key_count = existing_security_key_count
        @existing_passkey_count = existing_passkey_count
      end

      private

      delegate :parsed_useragent, :webauthn_register_request, :trusted_device_webauthn_sign_request, :mobile?, to: :helpers

      attr_reader :convert_for
      attr_reader :from_settings
      attr_reader :existing_security_key_count
      attr_reader :existing_passkey_count
    end
  end
end
