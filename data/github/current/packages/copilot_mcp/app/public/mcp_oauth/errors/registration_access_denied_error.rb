# typed: strict
# frozen_string_literal: true

require_relative "server_registration_error"

module McpOauth
  module Errors
    class RegistrationAccessDeniedError < ServerRegistrationError; end
  end
end
