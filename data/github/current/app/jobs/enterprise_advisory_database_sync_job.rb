# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class EnterpriseAdvisoryDatabaseSyncJob < ApplicationJob
  queue_as :advisory_database_sync

  schedule interval: 1.hour, condition: -> { GitHub.multi_tenant_enterprise? || GitHub.dotcom_connection_enabled? }

  LAST_RUN_AT_KEY = "#{self}.last_run_at".freeze
  CVE_EPSS_LAST_RUN_AT_KEY = "#{self}.cve_epss_last_run_at".freeze

  retry_on_dirty_exit
  exempt_from_tenant_context_requirement

  class SyncError < StandardError
  end

  # Note that last_run_at is only used for communicating about when the sync was last run, it is not used in any
  # delta calculation.
  def self.last_run_at
    AdvisoryDB::KV.store.get(LAST_RUN_AT_KEY).value { nil }&.to_i
  end

  # The approach of using KV is by-design, but within a short period of time (next week as of this writing) using KV
  # pointed at the notify cluster will be supported, which this and the persist_ method should move to.
  def self.get_cve_epss_last_updated_at
    AdvisoryDB::KV.store.get(CVE_EPSS_LAST_RUN_AT_KEY).value { nil }
  end

  def perform(updated_since: nil, force_all: false)
    GitHub.logger.with_named_tags("code.namespace" => "EnterpriseAdvisoryDatabaseSyncJob", "code.function" => "perform") do
      GitHub.logger.info("Starting Advisory Database sync with github.com")

      GitHub::Restraint.new.lock!("advisory_database_sync", 1, 1.day) do
        unless GitHub.multi_tenant_enterprise? || GitHub.dotcom_connection_enabled?
          GitHub.logger.info("Job run outside of connected enterprise environment, skipping sync with github.com")
          return
        end

        unless advisory_syncing_enabled?
          GitHub.logger.info("Connection settings missing, skipping sync with github.com")
          return
        end

        GitHub.logger.info("Syncing CWEs from github.com")
        sync_cwes

        if sync_cve_epss_enabled?
          GitHub.logger.info("Syncing CVE EPSS from github.com")
          sync_cve_epss
        end

        GitHub.logger.info("Syncing advisories from github.com")
        if force_all
          new_updated_since = nil
        else
          new_updated_since = updated_since.nil? ? Vulnerability.order(:updated_at).last&.updated_at : updated_since
        end
        sync_advisories(updated_since: new_updated_since)

        if @alerts_to_process.blank?
          GitHub.logger.info("No new/updated dependencies found, skipping dependency-graph-api sync")
        else
          GitHub.logger.info("Starting dependency-graph-api sync")
          DependencyGraph::CrossServiceJob.enqueue(job_class: "SyncVulnerabilitiesJob", args: [])

          GitHub.logger.info("Starting alert processing")
          process_alerts
        end

        GitHub.logger.info("Advisory Database sync with github.com completed")
      end
    end
  rescue GitHub::Restraint::UnableToLock
    GitHub.logger.info(
      "Another instance of job is running, skipping sync with github.com",
      "code.namespace" => "EnterpriseAdvisoryDatabaseSyncJob",
      "code.function" => "perform",
    )
    @job_skipped = true
  ensure
    if (GitHub.multi_tenant_enterprise? || GitHub.dotcom_connection_enabled?) && advisory_syncing_enabled? && !@job_skipped
      with_write do
        AdvisoryDB::KV.store.set(LAST_RUN_AT_KEY, Time.now.to_i.to_s)
      end
    end
  end

  private

  def advisory_syncing_enabled?
    advisory_database_app_enabled? || GitHub.ghe_content_analysis_enabled?
  end

  def authenticated_request(path, params = {})
    uri = URI("/advisory-database/#{path}")
    uri.query = params.to_query

    if GitHub.multi_tenant_enterprise?
      request = -> {
        faraday_connection.get do |req|
          req.url uri.to_s
          req.headers["Authorization"] = "token #{@access_token}"
          req.headers["Content-Type"] = "application/json"
        end
      }

      fetch_access_token unless @access_token.present? && @access_token_expires_at > Time.now

      response = request.call

      # if we get an unauthorized respose, lets try again with a fresh token
      # as it may have expired while the request was on its way to the server
      if response && response.status == 401
        fetch_access_token
        response = request.call
      end
    else
      response = GitHub::Connect.github_app_authenticated do
        github_connect_authenticator.enterprise_installation_api(uri.to_s, nil, GitHub::Connect.auth_headers, :get)
      end
    end

    response
  end

  def fetch_advisories(updated_since: nil, after: nil)
    advisories_response = authenticated_request("sync-advisories", { after: after, updated_since: updated_since })

    unless advisories_response.success?
      handle_fetch_error("advisories", __method__, advisories_response.body, should_raise: true)
    end

    advisories = JSON.parse(advisories_response.body)
    after_cursor = after_cursor_from_header(advisories_response)

    [advisories, after_cursor]
  rescue Timeout::Error, Faraday::TimeoutError, Net::OpenTimeout, Faraday::ConnectionFailed,
    GitHub::Connect::Authenticator::AuthenticationError, GitHub::Connect::Authenticator::ConnectionError => e
    handle_api_inaccessible_error("advisories", __method__, e, should_raise: true)
  end

  def fetch_cwes(page: nil)
    cwes_response = authenticated_request("sync-cwes", { page: page })

    unless cwes_response.success?
      handle_fetch_error("cwes", __method__, cwes_response.body, should_raise: false)
      return []
    end

    JSON.parse(cwes_response.body)
  rescue Timeout::Error, Faraday::TimeoutError, Net::OpenTimeout, Faraday::ConnectionFailed,
    GitHub::Connect::Authenticator::AuthenticationError, GitHub::Connect::Authenticator::ConnectionError => e
    handle_api_inaccessible_error("cwes", __method__, e, should_raise: false)
    []
  end

  def fetch_cve_epss(updated_since:, page:)
    cve_epss_response = authenticated_request("sync-cve-epss", { updated_since: updated_since, page: page })

    unless cve_epss_response.success?
      handle_fetch_error("cve-epss", __method__, cve_epss_response.body, should_raise: false)
      return []
    end

    JSON.parse(cve_epss_response.body)
  rescue Timeout::Error, Faraday::TimeoutError, Net::OpenTimeout, Faraday::ConnectionFailed,
    GitHub::Connect::Authenticator::AuthenticationError, GitHub::Connect::Authenticator::ConnectionError => e
    handle_api_inaccessible_error("cve-epss", __method__, e, should_raise: false)
    []
  end

  def handle_fetch_error(object_type, source_method, error_content, should_raise:)
    GitHub.logger.error(
      "API returned error while fetching #{object_type} from github.com",
      "code.namespace" => self.class.name,
      "code.function" => source_method.to_s,
      "exception.message" => error_content,
    )
    error = SyncError.new("API returned error while fetching #{object_type} from github.com: #{error_content}")
    if should_raise
      raise error
    else
      # the error won't be raised, so we make sure to get it to Failbot manually.
      # this mode is used for object types that aren't critical.
      Failbot.report(error)
    end
  end

  def handle_api_inaccessible_error(object_type, source_method, error, should_raise:)
    GitHub.logger.error(
      "API inaccessible while fetching #{object_type} from github.com",
      "code.namespace" => self.class.name,
      "code.function" => source_method.to_s,
      :exception => error,
    )
    error = SyncError.new("API inaccessible while fetching #{object_type} from github.com: #{error.message}")
    if should_raise
      raise error
    else
      # the error won't be raised, so we make sure to get it to failbot manually.
      Failbot.report(error)
    end
  end

  def process_advisory(vulnerability, advisory_data)
    vulnerable_version_range_ids_to_alert = []
    initial_cwe_ids = vulnerability.cwe_ids
    vulnerable_version_ranges = []

    saved_vulnerability = Vulnerability.transaction do
      # First, process the Vulnerability record.
      vulnerability_data = advisory_data.slice(*Vulnerability.attributes_for_enterprise)
      next unless vulnerability = save_record(vulnerability, vulnerability_data)

      # Then, process its associated records.
      Vulnerability.associations_for_enterprise.each do |association|
        next unless advisory_data[association].present?

        klass = Vulnerability.reflections[association].klass
        # Store the data in an indexed hash so we can break up processing in groups.
        association_hash = advisory_data[association].reduce({}) do |association_hash, association_data|
          association_hash[association_data["id"]] = association_data
          association_hash
        end

        process_association_record = -> (model, data_id) {
          data = association_hash[data_id].slice(*klass.attributes_for_enterprise)
          model = save_record(model, data)

          if model
            if model.class == VulnerableVersionRange
              # Need to process alerts and/or sync dep graph if one of the fields that affects those services has new data, see
              # https://github.com/github/dependency-graph-api/blob/72379ad279f363d1adf3d6ee52ce2ec932cdb5ba/app/models/vulnerable_version_range.rb#L50-L58 for details.
              if model.previous_changes_affect_alerts? || vulnerability.previous_changes_affect_alerts?
                vulnerable_version_range_ids_to_alert.push(model.id)
              end

              vulnerable_version_ranges.push(model)
            end

            model.id
          end
        }

        # First, update existing records so we can batch the SQL query.
        collection = vulnerability.public_send(association).where(id: association_hash.keys)
        processed_ids = collection.filter_map do |model|
          process_association_record.call(model, model.id)
        end

        # Then, add the new records.
        unprocessed_ids = association_hash.keys - processed_ids
        processed_ids += unprocessed_ids.filter_map do |id|
          model = vulnerability.public_send(association).build(id: id)
          process_association_record.call(model, id)
        end

        # Lastly, assign the resulting collection to the association in order to also delete
        # existing records which were not present in the data we got from dotcom.
        collection = vulnerability.public_send(association).where(id: processed_ids)
        vulnerability.public_send("#{association}=", collection)
      end

      vulnerability
    end

    return unless saved_vulnerability.present?

    # Committing the transaction always "touches" the record so we need to override
    # it to the one from dotcom that represents when actual advisory data was updated
    if advisory_data["updated_at"].present?
      saved_vulnerability.update_column(:updated_at, advisory_data["updated_at"])
    end

    if saved_vulnerability.status == "withdrawn" && saved_vulnerability.status_previously_changed?
      saved_vulnerability.enqueue_deletion_of_withdrawn_alerts
    end

    # Store alerts to be processed for after the dep graph has synced
    if saved_vulnerability.alertable? && vulnerable_version_range_ids_to_alert.any?
      @alerts_to_process ||= {}
      @alerts_to_process[saved_vulnerability.id] ||= []
      @alerts_to_process[saved_vulnerability.id].concat(vulnerable_version_range_ids_to_alert)
    end

    # If we're in Proxima mode check to see if existing alerts need to be updated
    # Cannot do this in GHES right now but we should circle back remove this check
    # when custom auto dismiss rules have been shipped in GHES.
    if GitHub.multi_tenant_enterprise?
      # Instrument a Dependabot alerts upstream change event if the vulnerability has changed
      cwes_changed = initial_cwe_ids.to_set != saved_vulnerability.cwe_ids.to_set
      instrument_dependabot_alert_upstream_change = saved_vulnerability.previous_changes.present? || cwes_changed
      have_instrumented_change = false

      if instrument_dependabot_alert_upstream_change
        upstream_changes = saved_vulnerability.previous_changes.keys
        upstream_changes << "cwe_ids" if cwes_changed

        have_instrumented_change = saved_vulnerability.instrument_dependabot_alerts_upstream_change(event: :update, changes: upstream_changes)
      end

      # Instrument a Dependabot alerts upstream change event for any of the VVRs that have changed
      # Note at this time we don't care about VVRs that are added or removed, only those that have changed
      unless have_instrumented_change
        vulnerable_version_ranges.select(&:instrument_vulnerability_update?).each do |vvr|
          vvr.instrument_dependabot_alerts_upstream_change(event: :update, changes: vvr.previous_changes.keys)
        end
      end
    end
  end

  def process_alerts
    vulnerability_ids = @alerts_to_process.keys
    vulnerability_ids.each_slice(100) do |vulnerability_ids_slice|
      vulnerabilities = Vulnerability.where(id: vulnerability_ids_slice)

      with_write do
        vulnerabilities.each do |vulnerability|
          vulnerability.process_alerts(range_ids: @alerts_to_process[vulnerability.id])
        end
      end
    end
  end

  def save_record(record, attributes)
    record.assign_attributes(attributes)
    record.save! if record.has_changes_to_save?
    record
  rescue ActiveRecord::RecordNotUnique => e
    # Advisories should never be deleted, but there have been a few exceptional cases where
    # this has happened in dotcom. The deletion does not propagate to other environments, but
    # the GHSA ID does return to the pool of available IDs. This means that if another advisory
    # comes through with that same GHSA, it will fail to save because the unique ID is already
    # taken. Knowing that this can only happen when the original advisory was deleted from dotcom,
    # we should delete our copy and try again.
    if record.class == Vulnerability && existing_ghsa = Vulnerability.find_by(ghsa_id: attributes["ghsa_id"])
      existing_ghsa.destroy!
      return save_record(Vulnerability.new, attributes)
    end

    Failbot.report(e, record.attributes)
    false
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    Failbot.report(e, record.attributes)
    false
  end

  def sync_advisories(updated_since: nil)
    # tiny buffer to make sure we don't lose anything on fractional seconds
    timestamp = updated_since ? updated_since - 1.minute : nil

    advisories, after = fetch_advisories(updated_since: timestamp)
    while advisories.present? do
      # Store the data in an indexed hash so we can break up processing in groups.
      advisories_hash = advisories.reduce({}) do |advisories_hash, advisory|
        advisories_hash[advisory["id"]] = advisory
        advisories_hash
      end

      # First, update existing records so we can batch the SQL query.
      vulnerabilities = Vulnerability.where(id: advisories_hash.keys)
      with_write do
        vulnerabilities.each { |vulnerability| process_advisory(vulnerability, advisories_hash[vulnerability.id]) }

        # Then, add the new records.
        unprocessed_ids = advisories_hash.keys - vulnerabilities.pluck(:id)
        unprocessed_ids.each { |unprocessed_id| process_advisory(Vulnerability.new, advisories_hash[unprocessed_id]) }
      end

      break unless after.present?

      advisories, after = fetch_advisories(updated_since: timestamp, after: after)
    end
  end

  def sync_cwes
    page = 1
    cwes = fetch_cwes(page: page)
    while cwes.present? do
      with_write do
        CWE.upsert_all(cwes, record_timestamps: false)
      end

      page += 1
      cwes = fetch_cwes(page: page)
    end
  end

  def sync_cve_epss
    page = 1

    # Similar to what advisory sync does, this is assuming the known issues around needing a buffer are correct
    # and replicating the buffer.
    timestamp = if self.class.get_cve_epss_last_updated_at.present?
      # 1.second / 100.0 = 10ms, buffer that should be well within 3 digit precision in milliseconds.
      # Why 1001.0? AFAIK this is a fractional math issue, but we don't reliably see the offset match expectations if
      # we use 1000.0 . In practice we don't expect this to impact the data we get, the number is technically a little under 10ms.
      (self.class.get_cve_epss_last_updated_at.to_time - 10 / 1001.0).utc.iso8601(3)
    else
      nil
    end

    cve_epss = fetch_cve_epss(updated_since: timestamp, page: page)

    while cve_epss.present? do
      latest_updated_at = cve_epss.last["updated_at"]
      cve_epss = cve_epss.map do |cve_epss_record|
        "#{cve_epss_record["cve_id"]},#{cve_epss_record["percentage"]},#{cve_epss_record["percentile"]}"
      end

      ingestion_date_proto = Google::Protobuf::Timestamp.new
      ingestion_date_proto.from_time(Time.now.utc)

      AdvisoryDB::CVEEPSSImporter.ingest_epss(
        source_of_ingest: "GHES Connect updated for timestamp: #{timestamp}",
        records_to_ingest: cve_epss,
        ingest_for_date: ingestion_date_proto.to_h
      )

      persist_cve_epss_last_updated_at(latest_updated_at) if sync_cve_epss_enabled?

      page += 1
      cve_epss = fetch_cve_epss(updated_since: timestamp, page: page)
    end
  end

  def sync_cve_epss_enabled?
    true
  end

  # The approach of using KV is by-design, but within a short period of time (next week as of this writing) using KV
  # pointed at the notify cluster will be supported, which this and the get_ method should move to.
  def persist_cve_epss_last_updated_at(latest_updated_at)
    with_write do
      AdvisoryDB::KV.store.set(CVE_EPSS_LAST_RUN_AT_KEY, latest_updated_at)
    end
  end

  # GHES connect communication

  def github_connect_authenticator
    @authenticator ||= GitHub::Connect::Authenticator.new
  end

  # Proxima cross-stamp communication

  def advisory_database_app_id
    ENV["ADVISORY_DATABASE_APP_ID"]
  end

  def advisory_database_app_installation_id
    ENV["ADVISORY_DATABASE_APP_INSTALLATION_ID"]
  end

  def advisory_database_app_enabled?
    advisory_database_app_id.present? && advisory_database_app_installation_id.present? && advisory_database_app_pem.present?
  end

  def advisory_database_app_pem
    ENV["ADVISORY_DATABASE_APP_PEM"]
  end

  def faraday_connection
    @connection ||= GitHub::FaradayClient::External.new({
      url: "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_api_host_name}",
    }) do |f|
      f.adapter Faraday.default_adapter
    end
  end

  def fetch_access_token
    payload = {
      # issued at time, 60 seconds in the past to allow for clock drift
      iat: Time.now.to_i - 60,
      # JWT expiration time (10 minute maximum)
      exp: Time.now.to_i + (10 * 60),
      iss: advisory_database_app_id,
    }
    private_key = OpenSSL::PKey::RSA.new(advisory_database_app_pem)
    jwt = JWT.encode(payload, private_key, "RS256")

    token_response = faraday_connection.post do |req|
      req.url "/app/installations/#{advisory_database_app_installation_id}/access_tokens"
      req.headers["Authorization"] = "Bearer #{jwt}"
      req.headers["Accept"] = "application/vnd.github+json"
    end

    unless token_response.success?
      GitHub.logger.error(
        "API returned error while fetching access token from github.com",
        "code.namespace" => "EnterpriseAdvisoryDatabaseSyncJob",
        "code.function" => "fetch_access_token",
        "exception.message" => token_response.body,
      )
      raise SyncError, "API returned error while fetching access token from github.com: #{token_response.body}"
    end

    body = JSON.parse(token_response.body)
    @access_token_expires_at = body["expires_at"]
    @access_token = body["token"]
  rescue Timeout::Error, Faraday::TimeoutError, Net::OpenTimeout, Faraday::ConnectionFailed => e
    GitHub.logger.error(
      "API inaccessible while fetching access token from github.com",
      "code.namespace" => "EnterpriseAdvisoryDatabaseSyncJob",
      "code.function" => "fetch_access_token",
      :exception => e,
    )
    raise SyncError, "API inaccessible while fetching access token from github.com: #{e.message}"
  end

  def cursor_from_header(response, which)
    return nil unless link_header = response.headers["Link"]
    regex = /#{which}=(?<cursor>[^&>]+)/
    return nil unless cursor = link_header.match(regex)&.captures&.first
    CGI.unescape(cursor)
  end

  def after_cursor_from_header(response)
    cursor_from_header(response, "after")
  end
end
