# typed: true
# frozen_string_literal: true

class Hook::Payload::ForkPayload < Hook::Payload

  def to_payload_hash
    {
      forkee: repo_hash_with_public_field(hook_event.fork_repository),
    }
  end

  private

  # Fork repo payloads include a `public` field in addition
  # to the `private` field which is part of the standard hash.
  # We should remove this in v4.
  def repo_hash_with_public_field(repo)
    api_serialize(:repository_hash, repo).tap do |repo_hash|
      repo_hash[:public] = repo.public?
    end
  end

end
