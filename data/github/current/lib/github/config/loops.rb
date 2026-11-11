# typed: strict
# frozen_string_literal: true

module GitHub

  # Loops-specific SimpleBox key management
  sig { returns(T.nilable(String)) }
  def self.loops_simple_box_key
    @loops_simple_box_key ||= T.let(ENV["LOOPS_SIMPLE_BOX_KEY"], T.nilable(String))
  end

  sig { params(key: T.nilable(String)).void }
  def self.loops_simple_box_key=(key = nil)
    @loops_simple_box_key = T.let(key, T.nilable(String))
  end

  sig { returns(T.nilable(RbNaCl::SimpleBox)) }
  def self.loops_simple_box
    RbNaCl::SimpleBox.from_secret_key(T.must(loops_simple_box_key).b) unless loops_simple_box_key.nil?
  end

  # Encrypt and encode a loops token using dedicated loops SimpleBox
  sig { params(token: T.nilable(String)).returns(T.nilable(String)) }
  def self.encrypt_and_encode_loops_token(token)
    return if token.nil? || loops_simple_box.nil?

    encrypted = T.must(loops_simple_box).encrypt(token)
    Base64.urlsafe_encode64(encrypted)
  end

  # Decode and decrypt a loops token using dedicated loops SimpleBox
  sig { params(encoded: T.nilable(String)).returns(T.nilable(String)) }
  def self.decode_and_decrypt_loops_token(encoded)
    return if encoded.nil? || loops_simple_box.nil?

    decoded = Base64.urlsafe_decode64(encoded)
    T.must(loops_simple_box).decrypt(decoded)
  end
end
