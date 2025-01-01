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
    @code_verifier = T.let(SecureRandom.urlsafe_base64, String)
    @code_challenge = T.let(generate_code_challenge(@code_verifier), String)
  end

  private

  sig { params(verifier: String).returns(String) }
  def generate_code_challenge(verifier)
    base64 = Digest::SHA256.base64digest(verifier)
    base64.tr("+/", "-_").delete("=") # URL-safe base64 encoding
  end
end
