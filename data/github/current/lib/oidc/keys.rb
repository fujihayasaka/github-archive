# typed: true
# frozen_string_literal: true

# This is a class that represent keys received from an IdP endpoint.
module OIDC
  class Keys
    KEYS = "keys"

    # Public: initialize keys
    def initialize(keys, error: nil)
      @keys = keys
      @valid = error.blank?
    end

    # Public: Checks if the parsing of JSON was correct
    #
    # Return Boolean
    def valid?
      @valid
    end

    # Public: Get an array of valid keys
    #
    # Return Array
    def signing_keys
      return @keys[KEYS] if valid?
      []
    end
  end
end
