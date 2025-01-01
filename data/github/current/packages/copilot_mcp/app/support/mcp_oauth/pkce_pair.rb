# typed: true
# frozen_string_literal: true

require "digest"
require "securerandom"

class McpOauth::PkcePair
  attr_reader :code_verifier, :code_challenge

  def self.generate
    new
  end

  def initialize
    @code_verifier = SecureRandom.urlsafe_base64
    @code_challenge = generate_code_challenge(@code_verifier)
  end

  private

  def generate_code_challenge(verifier)
    base64 = Digest::SHA256.base64digest(verifier)
    base64.tr("+/", "-_").delete("=") # URL-safe base64 encoding
  end
end
