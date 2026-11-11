# typed: strict
# frozen_string_literal: true

require "digest"
require "securerandom"

class McpOauth::PkcePair
  sig { returns(String) }
  attr_reader :code_verifier

  sig { returns(String) }
  attr_reader :code_challenge

  sig { returns(McpOauth::PkcePair) }
  def self.generate
    new
  end

  sig { void }
  def initialize
    # Explicitly specify number of bytes to get proper length for `code_verifier`.
    #
    # RFC 7636 requires a `code_verifier` between 43 and 128 chars. By default,
    # `urlsafe_base64` emits 16 bytes of random data, which results in 22 chars
    # output. 48 bytes of random data on the other hand results in 64 chars output.
    @code_verifier = T.let(SecureRandom.urlsafe_base64(48), String)
    @code_challenge = T.let(generate_code_challenge(@code_verifier), String)
  end

  private

  sig { params(verifier: String).returns(String) }
  def generate_code_challenge(verifier)
    base64 = Digest::SHA256.base64digest(verifier)
    base64.tr("+/", "-_").delete("=") # URL-safe base64 encoding
  end
end
