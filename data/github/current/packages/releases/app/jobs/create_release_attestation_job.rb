# typed: true
# frozen_string_literal: true

# Job to handle creation of release attestations
class CreateReleaseAttestationJob < ApplicationJob
  queue_as :release_attestation

  retry_on Releases::Error
  retry_on_recoverable_exceptions
  retry_on_dirty_exit

  # Perform release attestation in the background
  sig { params(release_id: Integer).void }
  def perform(release_id)
    release = ::Release.find(release_id)

    # Skip if the release is not in a state that can be attested
    return unless release.attestable?

    # Check to ensure the release has a tag name before attempting to attest it
    # This should not actually happen, but we have seen a few cases of this in production
    if release.tag.blank?
      GitHub.dogstats.increment("release.blank_tag_name", tags: ["state:published", "source:create_release_attestation_job"])
      GitHub.logger.warn("Release missing tag name",
        { "gh.release.id" => release_id, "gh.release.state" => "published", "gh.repo.id" => release.repository_id }
      )
      raise Releases::Error, "Release #{release_id} is missing a tag name, cannot attest release"
    end

    attestation_id = ReleaseAttestationManager.attest_release(release)

    with_write do
      release.update!(attestation_id: attestation_id)
    end
  end

  def failbot_context
    {
      "#job" => self.class.name,
      "#gh.release.id" => arguments.first
    }
  end
end
