# typed: true
# frozen_string_literal: true

# Represents an error occurring during provisioning

module Platform::Provisioning
  class IdentityRelinkError < Error
    def initialize(reason:, message: nil, current_identity_identifier: nil, new_identity_identifier: nil)
      @current_identity_identifier = current_identity_identifier
      @new_identity_identifier = new_identity_identifier
      @reason = reason
      @message = message
    end

    def current_identity_identifier
      @current_identity_identifier
    end

    def new_identity_identifier
      @new_identity_identifier
    end
  end
end
