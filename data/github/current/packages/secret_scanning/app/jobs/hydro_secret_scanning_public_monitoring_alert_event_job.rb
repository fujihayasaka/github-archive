# typed: strict
# frozen_string_literal: true

class HydroSecretScanningPublicMonitoringAlertEventJob < HydroMessageJob
  include SecretScanning::Features::FeatureFlagHelper
  include GitHub::Memoizer
  queue_as :hydro_secret_scanning_public_monitoring_alert_event

  retry_on_dirty_exit
  retry_on *T.unsafe(Resiliency::Response::UnavailableExceptions)
  retry_on Freno::Throttler::Error, Freno::Error, Freno::Throttler::WaitedTooLong

  FAILBOT_APP_NAME = "token-scanning-service"

  # Processes hydro messages for public monitoring alert events.
  #
  # Returns nothing
  sig { void }
  def perform
    process_event
  rescue => e
    Failbot.report(e, { app: FAILBOT_APP_NAME })
    raise e
  end

  private

  sig { void }
  def process_event
    enterprise_id = message[:enterprise_id]
    repository_id = message[:repository_id]
    secret_author_id = message[:secret_author_id]
    token_scan_result_id = message[:token_scan_result_id]
    public_monitoring_alert_id = message[:public_monitoring_alert_id]
    attribution_method = message[:attribution_method].presence || :ATTRIBUTION_METHOD_UNKNOWN

    ActiveRecord::Base.connected_to(role: :reading) do
      business = Business.find_by(id: enterprise_id)

      if business.nil?
        GitHub.logger.info(
          "Business not found, skipping message",
          "code.namespace": self.class.name,
          "gh.business.id": enterprise_id
        )
        return
      end

      GitHub::CurrentTenant.set(business) do
        unless ::SecretScanning::Features::Business::PublicMonitoring.new(business).enabled_for_apis_webhooks?
          GitHub.logger.info(
            "Public monitoring not enabled for business, skipping message",
            "code.namespace": self.class.name,
            "gh.business.id": enterprise_id
          )
          return
        end

        repo = Repository.find_by(id: repository_id)
        token_scan_result = TokenScanResult.find_by(id: token_scan_result_id)

        if token_scan_result.nil?
          GitHub.logger.info(
            "TokenScanResult not found, skipping message",
            "code.namespace": self.class.name,
            "gh.token_scan_result.id": token_scan_result_id
          )
          return
        end

        if repo.nil?
          GitHub.logger.info(
            "Repository not found, skipping message",
            "code.namespace": self.class.name,
            "gh.repository.id": repository_id
          )
          return
        end

        user = User.find_by(id: secret_author_id)
        committer_email = user&.git_author_email

        first_location = token_scan_result.first_location

        tss_client = GitHub::TokenScanning::Service::Client.new(nil)
        tss_response = tss_client.get_token(repository_id: repository_id, token_id: token_scan_result.number)
        if tss_response.nil? || tss_response.error.present?
          service_error = SecretScanning::Errors::ServiceError.new(
            "Failed to fetch token from TSS: #{tss_response&.error&.msg || "nil response"}"
          )
          Failbot.report(
            service_error,
            app: FAILBOT_APP_NAME,
            "gh.business.id": enterprise_id,
            "gh.repository.id": repository_id,
            "gh.alert_number": token_scan_result.number,
          )
          return
        end

        token = tss_response.data&.token
        Hook::Event::SecretScanningPublicMonitoringAlertEvent.queue(
          action: :created,
          business_id: enterprise_id,
          public_monitoring_alert_id: public_monitoring_alert_id,
          slug: token&.slug,
          label: token&.label,
          created_at: token_scan_result.created_at&.utc&.iso8601,
          repository_id: repository_id,
          repository_name: repo.name_with_display_owner,
          committer_email: committer_email,
          secret_author_id: secret_author_id,
          token_scan_result_id: token_scan_result_id,
          alert_number: token_scan_result.number,
          location_id: first_location&.id,
          attribution_method: attribution_method,
        )

        GitHub.logger.info(
          "secret_scanning_public_monitoring_alert.created delivery queued",
          "code.namespace": self.class.name,
          "gh.business.id": enterprise_id,
          "gh.alert_number": token_scan_result.number
        )
      end
    end
  end
end
