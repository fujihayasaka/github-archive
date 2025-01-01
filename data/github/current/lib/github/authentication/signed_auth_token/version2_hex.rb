# typed: true
# frozen_string_literal: true

class GitHub::Authentication::SignedAuthToken::Version2Hex < GitHub::Authentication::SignedAuthToken::Version2
  # Regex that generated tokens should match.
  #
  # Returns a Regexp instance.
  def self.token_regex
    /\A[a-zA-Z0-9]{62,}\z/
  end

  # Encode a token as hex.
  #
  # token - A binary String token.
  #
  # Returns an encoded String token.
  def self.encode(token)
    token.unpack("H*").first
  end

  # Decode a token as hex.
  #
  # token - An encoded String token.
  #
  # Returns an binary String token.
  def self.decode(token)
    [token].pack("H*")
  end

  # The version of SignedAuthToken.
  #
  # Returns an Symbol.
  def version
    :hex
  end
end
