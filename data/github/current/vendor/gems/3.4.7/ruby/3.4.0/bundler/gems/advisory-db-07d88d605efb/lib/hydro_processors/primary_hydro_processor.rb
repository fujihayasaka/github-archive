# frozen_string_literal: true

require "hydro"

class PrimaryHydroProcessor < Hydro::Processor
  UnknownHydroMessageError = Class.new(::StandardError)

  attr_reader :msg_id, :msg_value

  # handle a batch of AdvisoryPrediction hydro messsages
  def process_with_consumer(batch, consumer)
    batch.each { |message| process_message(message, consumer) }
  end

  def batching?
    true
  end

  private

  def process_message(message, consumer)
    @msg_id = message.id
    @msg_value = message.value
    ::GitHub::Telemetry::Logs.logger.info(
      "Got hydro message",
      "gh.hydro.msg.schema": message.schema,
      "gh.hydro.msg.id": @msg_id,
      "gh.hydro.msg.value": @msg_value,
      "gh.hydro.msg.topic": message.topic,
    )

    case message.topic
    when /v0\.AdvisoryPrediction\z/
      process_advisory_prediction

    when /v0\.CVERequest\z/
      process_cve_request

    when /v0\.RepositoryAdvisoryCurationRequest\z/
      process_repository_advisory_curation_request

    when /v0\.MalwareAdvisories\z/
      process_malware_advisories

    when /v0\.AdvisoryAlertingEvent\z/
      process_advisory_alerting_event
    else
      raise UnknownHydroMessageError, "Unknown hydro message received for topic: #{message.topic}"
    end

    AdvisoryDB.stats.increment("hydro.process", {
      tags: AdvisoryDB.dogtags(schema: message.schema, topic: message.topic),
    })

    # We have `automatically_mark_as_processed: false` configured, so we must manually mark processed
    consumer.mark_message_as_processed(message)
  rescue StandardError => error
    # catch all errors and keep processing
    # without this, the processor dies and causes production to break
    Failbot.report!(error)
  end

  def process_advisory_prediction
    ProcessAdvisoryPredictionJob.perform_later(
      identifier: msg_value[:identifier],
      reject_prediction: msg_value[:reject_prediction].to_s,
    )
  end

  def process_cve_request
    # clear active connections to avoid this exception: Mysql2::Error::ConnectionError: MySQL server has gone away
    # more info: https://github.com/github/dsp-security-workflows/issues/956
    ActiveRecord::Base.connection_handler.clear_active_connections!(role: ActiveRecord::Base.current_role)

    severity = msg_value[:repository_advisory][:severity].downcase
    severity = nil if severity == "severity_unknown"

    cve_request = CVERequest.create!(
      ghsa_id: msg_value[:repository_advisory][:ghsa_id],
      actor_id: msg_value[:actor][:id],
      actor_login: msg_value[:actor][:login],
      advisory_permalink: msg_value[:repository_advisory][:permalink],
      advisory_state: msg_value[:repository_advisory][:state],
      title: msg_value[:title],
      description: msg_value[:description],
      severity: severity,
      cvss_v3: msg_value[:cvss_v3],
      cvss_v4: msg_value[:cvss_v4],
      affected_products_payload: msg_value[:affected_products]&.map do |affected_product|
        {
          ecosystem: affected_product[:package_ecosystem],
          package: affected_product[:package_name],
          affected_versions: affected_product[:vulnerable_version_range],
          patches: affected_product[:first_patched_version],
        }
      end,
    )

    ResolveCVERequestJob.perform_later(cve_request.id)
  end

  def process_repository_advisory_curation_request
    curation_data = RepositoryAdvisoryCurationData.create_from_repository_advisory_hydro_message(msg_value)
    ProcessRepositoryAdvisoryCurationRequestJob.perform_later(repo_advisory_curation_data_hash: curation_data.to_h)
  end

  def process_malware_advisories
    ProcessMalwareAdvisoriesJob.perform_later(msg_value)
  end

  def process_advisory_alerting_event
    ProcessAdvisoryAlertingEventJob.perform_later(msg_value)
  end
end
