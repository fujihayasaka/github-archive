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

      # Invalid or tampered cursor — surface as cursor-not-found so the
      # controller can render a 404 instead of a misleading empty list.
      if Services::ServiceHelper.cursor_error?(response)
        return PublicMonitoringAlertListResponse.empty(status: PublicMonitoringAlertListResponse::Status::CursorNotFound)
      end

      is_err, _err = Services::ServiceHelper.process_response(
        response: response,
        operation: "loading public monitoring alerts",
        is_404_ok: false,
        failbot_attributes: { business_id: business.id },
      )
      if is_err || response.nil?
        return PublicMonitoringAlertListResponse.empty(status: PublicMonitoringAlertListResponse::Status::ServiceError)
      end

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
      total_count = (count_is_err || count_response.nil?) ? alerts.length : count_response.data.total_count.to_i

      repos_by_id = get_repos_from_alerts(alerts)
      users_by_id = get_users_from_alerts(alerts)

      # Defense-in-depth: filter out alerts whose repository is no longer
      # public (or was deleted from dotcom).  TSS applies this filter at
      # query time, but there is a brief sync-lag window after a repo goes
      # private/deleted before TSS processes the hydro event.  Filtering
      # here ensures neither the UI nor the API ever surfaces such alerts.
      alerts = alerts.select { |alert| repos_by_id[alert.repository_id]&.public? }

      locations_by_key = get_first_locations_from_alerts(client, alerts, repos_by_id)

      PublicMonitoringAlertListResponse.new(
        alerts: alerts.map { |alert| build_alert(alert, business.id, repos_by_id, users_by_id, locations_by_key) },
        total_count: total_count,
        next_cursor: encode_cursor(data.next_cursor),
        previous_cursor: encode_cursor(data.previous_cursor),
      )
    end

    sig { params(business: Business).returns(T::Array[String]) }
    def self.verified_domains_for(business:)
      business_owned = VerifiableDomain.verified
        .where(owner_type: "Business", owner_id: business.id)
        .pluck(:domain)
      org_owned = VerifiableDomain.verified
        .where(owner_type: "User", owner_id: business.organization_ids)
        .pluck(:domain)
      (business_owned + org_owned).uniq.sort
    end

    sig { params(raw: T.nilable(String)).returns(T.nilable(String)) }
    private_class_method def self.encode_cursor(raw)
      return nil if raw.blank?

      Base64.urlsafe_encode64(raw, padding: false)
    end

    sig do
      params(
        alert: GitHub::Proto::SecretScanning::PublicMonitoring::V1::PublicMonitoringAlert,
        business_id: Integer,
        repos_by_id: T::Hash[Integer, Repository],
        users_by_id: T::Hash[Integer, User],
        locations_by_key: T::Hash[String, GitHub::TokenScanning::Service::TokenLocation],
      ).returns(PublicMonitoringAlert)
    end
    private_class_method def self.build_alert(alert, business_id, repos_by_id, users_by_id, locations_by_key)
      repo = repos_by_id[alert.repository_id]
      user = users_by_id[alert.secret_author_id]
      location_key = "#{alert.repository_id}:#{alert.alert_number}"
      location = locations_by_key[location_key]

      pubmon_alert = PublicMonitoringAlert.from_proto(
        alert,
        business_id: business_id,
        repository: repo,
        repository_name: repo&.name_with_display_owner || "Unknown repository",
        committer_identifier: user ? user.display_login : User.ghost.display_login,
        committer_email: user&.git_author_email,
        committer_avatar_url: user ? user.primary_avatar_url : User.ghost.primary_avatar_url,
        secret_author: user || User.ghost,
        first_location: location,
      )
      # Only decrypt if we can confirm the repo is currently public.
      # Missing repo (deleted) or private/internal repo => keep secret redacted.
      if repo&.public?
        SecretScanning::Encryption::EncryptedSecretsHelper.set_raw_secret_from_encrypted_secret(pubmon_alert)
      end
      pubmon_alert
    end

    sig do
      params(
        client: GitHub::TokenScanning::Service::Client,
        alerts: T::Array[GitHub::Proto::SecretScanning::PublicMonitoring::V1::PublicMonitoringAlert],
        repos_by_id: T::Hash[Integer, Repository],
      ).returns(T::Hash[String, GitHub::TokenScanning::Service::TokenLocation])
    end
    private_class_method def self.get_first_locations_from_alerts(client, alerts, repos_by_id)
      locations = T.let({}, T::Hash[String, GitHub::TokenScanning::Service::TokenLocation])
      return locations if alerts.empty?

      alerts.each do |alert|
        repo = repos_by_id[alert.repository_id]
        next unless repo

        response = client.get_token(
          repository_id: alert.repository_id,
          token_id: alert.alert_number.to_i,
        )
        next if response.nil? || response.error.present?

        data = response.data
        next if data.nil?

        token = data.token
        next if token.nil? || token.first_location.blank?

        key = "#{alert.repository_id}:#{alert.alert_number}"
        locations[key] = GitHub::TokenScanning::Service::TokenLocation.new(token.first_location, repo)
      end

      locations
    end

    sig { params(alerts: T::Array[GitHub::Proto::SecretScanning::PublicMonitoring::V1::PublicMonitoringAlert]).returns(T::Hash[Integer, Repository]) }
    private_class_method def self.get_repos_from_alerts(alerts)
      repo_ids = alerts.map(&:repository_id).uniq
      return {} if repo_ids.empty?

      repos_by_id = T.let({}, T::Hash[Integer, Repository])
      Repository.active.where(id: repo_ids).each { |r| repos_by_id[r.id] = r }
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
