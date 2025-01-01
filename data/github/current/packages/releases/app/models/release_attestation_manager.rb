# typed: true
# frozen_string_literal: true

require "monolith-twirp-attester"
require "sigstore-proto"

module ReleaseAttestationManager

  # Coordinates the workflow for generating and publishing a release attestation
  sig { params(release: Release).returns(Integer) }
  def self.attest_release(release)
    repository = T.must(release.repository)

    # Assemble the in-toto statement with the release information
    statement = ReleaseStatementCreator.assemble_statement(release)

    # Send the statement to the attester for signing
    response = ReleaseAttester.attest_release(statement)

    if !response.call_succeeded?
      raise Releases::Error,
        "Failed to attest release (#{response.status}) #{response.options[:message]}"
    end

    # Send the signed attestation to TMA for persistence
    msg = T.let(response.value, MonolithTwirp::Attester::V0::CreateReleaseAttestationResponse)
    response = TrustMetadata.create_release_attestation(repository, T.must(msg.bundle))

    if !response.call_succeeded?
      raise Releases::Error,
        "Failed to persist release attestation (#{response.status}) #{response.options[:message]}"
    end

    # Return the attestation ID from the response
    T.let(response.value, Proto::TrustMetadataApi::V0::CreateReleaseAttestationResponse).attestation_id
  end
end
