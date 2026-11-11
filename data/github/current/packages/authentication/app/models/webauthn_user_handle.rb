# typed: true
# frozen_string_literal: true

class WebauthnUserHandle < ApplicationRecord::Collab
  belongs_to :user

  validates :webauthn_user_handle, presence: true

  # Looks up the webauthn user handle for the given user; creates if needed.
  # Returns a binary string.
  def self.lookup(user)
    record = retry_on_find_or_create_error do
      WebauthnUserHandle.find_by(user_id: user.id) || WebauthnUserHandle.create(user_id: user.id)
    end
    record.webauthn_user_handle
  end

  # Generate a unique 64-byte random value associated with the user, as
  # recommended by the webauthn spec:
  # https://www.w3.org/TR/webauthn/#sctn-user-handle-privacy
  def self.generate_value
    SecureRandom.bytes(64)
  end
end
