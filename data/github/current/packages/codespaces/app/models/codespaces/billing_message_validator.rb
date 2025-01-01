# typed: true
# frozen_string_literal: true

require "json"
require "json-schema"

module Codespaces
  module BillingMessageValidator
    JSON_SCHEMA_PATH = "#{__dir__}/../../schema/vscs_billing_schema.json"

    def validate_message(message_body:, fragment_path:)
      JSON::Validator.fully_validate(JSON_SCHEMA_PATH, message_body, fragment: fragment_path)
    end
  end
end
