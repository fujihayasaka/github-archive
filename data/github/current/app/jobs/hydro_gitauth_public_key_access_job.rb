# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroGitauthPublicKeyAccessJob < HydroMessageJob
  queue_as :hydro_gitauth_public_key_access
  retry_on_dirty_exit

  sig { void }
  def perform
    id = message[:public_key_id]
    public_key = PublicKey.find_by(id:)

    return if public_key.nil?

    PublicKey.access(id:, last_accessed_at: public_key.accessed_at)
  end
end
