# typed: true
# frozen_string_literal: true

# Job to handle deletion of release attestations
class DeleteReleaseAttestationJob < ApplicationJob
  queue_as :release_attestation

  retry_on Releases::Error
  retry_on_recoverable_exceptions
  retry_on_dirty_exit

  # Delete release attestation in the background
  sig { params(repo_id: Integer, attestation_id: Integer).void }
  def perform(repo_id, attestation_id)
    repo = Repositories::Public.get_active_or_deleted!(repo_id)

    # Call the TrustMetadata service to delete the attestation
    response = TrustMetadata.delete_github_attestation_by_id(repo, attestation_id)

    if !response.call_succeeded?
      raise Releases::Error,
        "Failed to delete release attestation (#{response.status}) #{response.options[:message]}"
    end
  end

  def failbot_context
    {
      "#job" => self.class.name,
      "gh.repo.id" => arguments[0],
      "gh.attestation.id" => arguments[1]
    }
  end
end
