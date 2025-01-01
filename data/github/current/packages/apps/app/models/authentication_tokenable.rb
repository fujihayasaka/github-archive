# typed: true
# frozen_string_literal: true

module AuthenticationTokenable
  extend T::Helpers
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(ApplicationRecord::Base))

    has_many :tokens,
      as:         :authenticatable,
      class_name: "AuthenticationToken"

    destroy_dependents_in_background :tokens
  end

  # Public: Generates a new AuthenticationToken for this record and
  # returns the token's plaintext value for use in making authenticated API
  # requests.
  #
  # Returns a String.
  def generate_token(code_path: AuthenticationToken::UNKNOWN_CODE_PATH)
    _, value = AuthenticationToken.create_for(self, code_path: code_path)

    value
  end
end
