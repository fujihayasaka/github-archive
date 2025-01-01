# typed: true
# frozen_string_literal: true

require "github/kredz_client"

module Actions
  module Secrets
    class AddSecretForm < ApplicationForm

      form do |add_secrets_form|
        add_secrets_form.text_field(
          label: "Name",
          name: "secret_name",
          placeholder: "YOUR_SECRET_NAME",
          required: true,
          maxlength: GitHub::KredzClient::Credz::SECRET_KEY_MAX_SIZE
        )
        add_secrets_form.text_area(
          label: "Secret",
          name: "secret_value",
          required: true,
          rows: 9
        )

        add_secrets_form.hidden(name: :encrypted_value)
        add_secrets_form.hidden(name: :key_id, value: @key_id)

        add_secrets_form.submit(name: "Add secret", label: "Add secret", scheme: :primary)
      end

      def initialize(key_id:)
        @key_id = key_id
      end
    end
  end
end
