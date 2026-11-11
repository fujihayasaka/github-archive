# typed: strict
# frozen_string_literal: true

module SecretScanning
  # Fetches public monitoring alerts for an enterprise from TSS via Twirp.
  class PublicMonitoringQueryService
    sig do
      params(
        business: Business,
        current_user: User,
        cursor: T.nilable(String),
        per_page: Integer,
      ).returns(PublicMonitoringAlertListResponse)
    end
    def self.list_alerts(business:, current_user:, cursor: nil, per_page: 25)
      req = GitHub::Proto::SecretScanning::PublicMonitoring::V1::ListAlertsRequest.new(
        business_id: business.id,
        limit: per_page,
        cursor: cursor || "",
      )

      client = GitHub::TokenScanning::Service::Client.new(current_user)
      response = client.list_public_monitoring_alerts(req)

      # Suppress Failbot for cursor deserialization errors (user-edited URLs).
      if Services::ServiceHelper.cursor_error?(response)
        return PublicMonitoringAlertListResponse.empty
      end

      is_err, _err = Services::ServiceHelper.process_response(
        response: response,
        operation: "loading public monitoring alerts",
        is_404_ok: false,
        failbot_attributes: { business_id: business.id },
      )
      return PublicMonitoringAlertListResponse.empty if is_err || response.nil?

      data = response.data
      alerts = data.alerts.to_a

      # Fetch total count via separate RPC.
      count_req = GitHub::Proto::SecretScanning::PublicMonitoring::V1::CountAlertsRequest.new(
        business_id: business.id,
      )
      count_response = client.count_public_monitoring_alerts(count_req)
      count_is_err, _count_err = Services::ServiceHelper.process_response(
        response: count_response,
        operation: "counting public monitoring alerts",
        is_404_ok: false,
        failbot_attributes: { "gh.business.id" => business.id },
      )
      total_count = (count_is_err || count_response.nil?) ? 0 : count_response.data.total_count.to_i

      repos_by_id = get_repos_from_alerts(alerts)
      users_by_id = get_users_from_alerts(alerts)

      PublicMonitoringAlertListResponse.new(
        alerts: alerts.map { |alert| build_alert(alert, repos_by_id, users_by_id) },
        total_count: total_count,
        next_cursor: encode_cursor(data.next_cursor),
        previous_cursor: encode_cursor(data.previous_cursor),
      )
    end

    sig { params(raw: T.nilable(String)).returns(T.nilable(String)) }
    private_class_method def self.encode_cursor(raw)
      return nil if raw.blank?

      Base64.urlsafe_encode64(raw, padding: false)
    end

    sig do
      params(
        alert: GitHub::Proto::SecretScanning::PublicMonitoring::V1::PublicMonitoringAlert,
        repos_by_id: T::Hash[Integer, Repository],
        users_by_id: T::Hash[Integer, User],
      ).returns(PublicMonitoringAlert)
    end
    private_class_method def self.build_alert(alert, repos_by_id, users_by_id)
      repo = repos_by_id[alert.repository_id]
      user = users_by_id[alert.secret_author_id]

      pubmon_alert = PublicMonitoringAlert.from_proto(
        alert,
        repository_name: repo&.name_with_display_owner || "Unknown repository",
        committer_identifier: user ? user.display_login : User.ghost.display_login,
        committer_email: user&.git_author_email,
        committer_avatar_url: user ? user.primary_avatar_url : User.ghost.primary_avatar_url,
      )
      SecretScanning::Encryption::EncryptedSecretsHelper.set_raw_secret_from_encrypted_secret(pubmon_alert)
      pubmon_alert
    end

    sig { params(alerts: T::Array[GitHub::Proto::SecretScanning::PublicMonitoring::V1::PublicMonitoringAlert]).returns(T::Hash[Integer, Repository]) }
    private_class_method def self.get_repos_from_alerts(alerts)
      repo_ids = alerts.map(&:repository_id).uniq
      return {} if repo_ids.empty?

      repos_by_id = T.let({}, T::Hash[Integer, Repository])
      Repository.where(id: repo_ids).each { |r| repos_by_id[r.id] = r }
      repos_by_id
    end

    sig { params(alerts: T::Array[GitHub::Proto::SecretScanning::PublicMonitoring::V1::PublicMonitoringAlert]).returns(T::Hash[Integer, User]) }
    private_class_method def self.get_users_from_alerts(alerts)
      user_ids = alerts.map(&:secret_author_id).uniq
      return {} if user_ids.empty?

      users_by_id = T.let({}, T::Hash[Integer, User])
      User.where(id: user_ids).each { |u| users_by_id[u.id] = u }
      users_by_id
    end
  end
end
