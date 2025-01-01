# typed: true
# frozen_string_literal: true

class VulnerabilitiesTransitionSyncJob < ApplicationJob
  queue_as :vulnerabilities_transition_sync
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  RETRYABLE_ERRORS = [
    ActiveRecord::RecordNotFound,
    WaitForReplication::DataUnavailable
  ]

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 5) do |job, error|
    job.report_error(error)
  end

  class ConversionNotAllowedError < StandardError; end

  class VulnerabilitySyncUnsuccessfulError < StandardError; end

  class Vulnerability < ApplicationRecord::Domain::Vulnerabilities
    self.table_name = :vulnerabilities

    def self.converts_to
      ScopedVulnerability
    end

    def converted_attributes
      attributes.merge({ "id": id, "scope": "open_source", "advisory_repository_id": 0, "security_advisory_id": 0 })
    end

    def open_source?
      true
    end
  end

  class ScopedVulnerability < ApplicationRecord::Domain::Vulnerabilities
    self.table_name = :scoped_vulnerabilities

    def self.converts_to
      Vulnerability
    end

    def converted_attributes
      raise ConversionNotAllowedError.new("Attempted to convert a innersource vulnerability") if scope == "innersource"
      attributes.without("scope", "advisory_repository_id", "security_advisory_id")
    end

    def open_source?
      scope == "open_source"
    end
  end

  def perform(vulnerability_id, direction: self.class.default_sync_direction, range_ids_to_alert: [])
    return unless self.class.enabled?

    @direction = direction
    @vulnerability_id = vulnerability_id

    start_table = @direction == :to_scoped_vulnerabilities ? Vulnerability : ScopedVulnerability
    end_table = start_table.converts_to

    end_table.throttle do
      vulnerability = start_table.find_by!(id: @vulnerability_id)
      return unless vulnerability.open_source?

      # need to track the previous attributes for triggering callbacks manually
      if @direction == :to_vulnerabilities
        previous_attributes = end_table.find_by(id: @vulnerability_id)&.attributes
      end

      start_time = Time.now

      with_write do
        end_table.upsert(vulnerability.converted_attributes, record_timestamps: false)
      end

      waiter = WaitForReplication.new(Timestamp.from_time(start_time), store_name: end_table.cluster_name)
      waiter.wait!

      synced_vulnerability = end_table.find_by(id: @vulnerability_id)
      raise_sync_error(start_table) unless synced_vulnerability

      GitHub.dogstats.timing_since("vulnerabilities_transition_sync.replication.duration", start_time, tags: stats_tags)

      if @direction == :to_vulnerabilities
        vuln = ::Vulnerability.find_by(id: synced_vulnerability.id)
        raise_sync_error(start_table) unless vuln

        if vuln
          with_write do
            AdvisoryDB::ScopedVulnerabilityHelper.process_alerts(vuln, range_ids_to_alert)

            # need to trigger callbacks manually given that we are upserting into the table
            vuln.run_callbacks_in_sync(previous_attributes)
          end
        end
      end

      instrument_job_run
    end
  end

  def self.enabled?
    AdvisoryDB::ScopedVulnerabilityHelper.sync_enabled?
  end

  def self.default_sync_direction
    if AdvisoryDB::ScopedVulnerabilityHelper.syncing_to_vulnerabilities?
      :to_vulnerabilities
    else
      :to_scoped_vulnerabilities
    end
  end

  def instrument_job_run
    GitHub.dogstats.increment("vulnerabilities_transition_sync.run", tags: stats_tags)
  end

  # This also adds additional stats to error dogstats
  # defined in ApplicationJob
  def stats_tags
    ["sync_direction:#{@direction}"]
  end

  def job_context
    {
      vulnerability_id: @vulnerability_id,
      direction: @direction,
    }
  end

  def raise_sync_error(start_table)
    raise VulnerabilitySyncUnsuccessfulError.new("#{start_table.class.name} id #{@vulnerability_id} was not synced successfully.")
  end

  def failbot_context
    super.merge(job_context)
  end

  def report_error(error)
    Failbot.report(error, failbot_context)
  end
end
