# typed: true
# frozen_string_literal: true

module Api::Serializer::VerifiableDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer }

  # Creates a hash of data about a commit or tag's signature.
  #
  # object  - A Commit or Tag instance.
  # options - Hash.
  #
  # Returns a Hash.
  def verification_hash(object, options = {})
    h = {
      verified: object.verified_signature?,
      reason: object.signature_verification_reason,
      signature: object.signature,
      payload: object.signing_payload,
    }

    h[:verified_at] = time(object.signature_verified_at) if object.repository&.feature_enabled?(:signature_verified_at)

    h
  end
end
