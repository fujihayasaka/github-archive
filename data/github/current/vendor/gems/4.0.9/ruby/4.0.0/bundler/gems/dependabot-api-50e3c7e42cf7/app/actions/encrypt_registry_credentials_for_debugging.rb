# frozen_string_literal: true

require "secret_fetcher"

# This action is used to encrypt the registry secrets for debugging purposes.
# Given an UpdateConfig and public key, it will encrypt any configured secrets
# and return those encrypted secrets as a base64-encoded string.
class EncryptRegistryCredentialsForDebugging
  # Generated blobs are prefixed so we can:
  # - Search arbitary content for potentially leaked tokens
  # - Relate any tokens found in the wild to this source code via search
  PREFIX = "ghx_dep_"

  DebugCredentials = Struct.new(:encrypted_credential_blob, keyword_init: true)
  # We need to pass something that quacks like an UpdateJob to the serializer
  DebugUpdateJob = Struct.new(:id, :update_config, :accessible_github_repo_ids, keyword_init: true) do
    def telemetry_attributes
      {
        "gh.update_job.id": "debug_update_job",
      }.merge(**update_config.telemetry_attributes)
    end
  end

  def initialize(update_config, public_key)
    @update_config = update_config
    @public_key = public_key
  end

  def run
    DebugCredentials.new(
      encrypted_credential_blob: PREFIX + Base64.strict_encode64(encrypted_credential_blob),
    )
  end

  private

  attr_reader :update_config

  def encryption_key
    Base64.strict_decode64(@public_key)
  end

  def encrypted_credential_blob
    plaintext_credentials = UpdateJobCredentialsSerializer.new(
      DebugUpdateJob.new(
        id: update_config.id,
        update_config: update_config,
        accessible_github_repo_ids: update_config.accessible_github_repo_ids
      )
    ).credentials.to_json

    encrypted_box.encrypt(plaintext_credentials)
  end

  def encrypted_box
    RbNaCl::SealedBox.from_public_key(encryption_key)
  end
end
