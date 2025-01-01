# typed: true
# frozen_string_literal: true

module Api::Serializer::VerifiableDependency
  # Creates a hash of data about a commit or tag's signature.
  #
  # object  - A Commit or Tag instance.
  # options - Hash.
  #
  # Returns a Hash.
  def verification_hash(object, options = {})
    {
      verified: object.verified_signature?,
      reason: object.signature_verification_reason,
      signature: object.signature,
      payload: object.signing_payload,
    }
  end
end
