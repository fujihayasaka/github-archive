# typed: true
# frozen_string_literal: true

class HydroSecretScanningTokenRevocationJob < HydroMessageJob
  include GitHub::TokenScanning::TokenScanningPostProcessingHelper

  queue_as :hydro_secret_scanning_token_revocation

  retry_on_dirty_exit
  retry_on *T.unsafe(Resiliency::Response::UnavailableExceptions)
  retry_on Freno::Throttler::Error, Freno::Error, Freno::Throttler::WaitedTooLong

  # HydroSecretScanningTokenRevocationJob sends email notifications when PATv2s
  # are revoked. PATv2s are revoked after a scan through a call in TSS to Authnd,
  # so the email notification has to be sent separately
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

    if FeatureFlag.vexi.enabled?(:secret_scanning_use_notification_service, default: false)
      service = SecretScanning::NotificationService.new(caller_namespace: "HydroSecretScanningTokenRevocationJob")
      service.deliver_revoked_token_notification(
        target: repo,
        user: user,
        token_source: message[:token_source],
        url: message[:url],
        token_type: "GITHUB_TOKEN_V2",
        is_expired: false,
      )
    else
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
end
