# typed: true
# frozen_string_literal: true

class HydroSecretScanningTokenRevocationJob < HydroMessageJob
  include GitHub::TokenScanning::TokenScanningPostProcessingHelper

  queue_as :hydro_secret_scanning_token_revocation

  retry_on_dirty_exit
  retry_on *T.unsafe(Resiliency::Response::UnavailableExceptions)
  retry_on Freno::Throttler::Error, Freno::Error, Freno::Throttler::WaitedTooLong

  # HydroSecretScanningTokenRevocationJob extracts just the mailer portion of
  # lib/github/token_scanning/token_revocation_helper.rb. Results on this hydro
  # topic are access tokens assumed to have been revoked by AuthnD.
  def perform
    user = User.find_by(id: message[:token_user_id])
    if user.nil?
      Failbot.report(StandardError.new("user with id could not be found"), user_id: message[:token_user_id])
      return
    end

    repo = get_repo_from_request(message[:repository_type], message[:repository_id])

    if repo.nil?
      Failbot.report(StandardError.new("repo could not be found"), repository_id: message[:repository_id], repository_type: message[:repository_type])
      return
    end

    # Only include the URL if the repository is readable by the user
    # so private repository links are not leaked to users without access
    url = message[:url] if repo.readable_by?(user)

    token_source = message[:token_source]
    if message[:repository_type] == :GIST
      # Need to set source to :GIST because it's otherwise :CONTENT
      token_source = :GIST
    end

    SecretScanningMailer.personal_access_token_leaked(repo, user, token_source, url, token_type: "GITHUB_TOKEN_V2", key_name: nil).deliver_later
  end
end
