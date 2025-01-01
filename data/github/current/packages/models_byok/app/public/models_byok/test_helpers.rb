# typed: strict
# frozen_string_literal: true

require "diet_earthsmoke"

module ModelsByok
  module TestHelpers
    sig { params(plaintext: String, owner: ::Organization).returns(String) }
    def encrypt_plaintext(plaintext, owner)
      public_key_id, encoded_public_key = ::ModelsByok::CustomKey.encryption_public_key(owner)
      # Encrypt the secret as the client would, per https://developer.github.com/v3/actions/secrets/#example-encrypting-a-secret-using-ruby
      public_key = RbNaCl::PublicKey.new(Base64.decode64(encoded_public_key))
      box = RbNaCl::Boxes::Sealed.from_public_key(public_key)
      encrypted = box.encrypt(plaintext)
      Base64.strict_encode64(encrypted)
    end
  end
end
