# typed: false
# frozen_string_literal: true

module Insights::EntityInstrumenter
  extend ActiveSupport::Concern
  included do
    after_create_commit  -> { enqueue_instrument_insights_entity_job("insights.entity_created") }
    after_update_commit  -> { enqueue_instrument_insights_entity_job("insights.entity_updated") }
    after_destroy_commit -> { enqueue_instrument_insights_entity_destroyed_job }
  end

  def insights_enabled?
    Insights::Access.enabled?(self.insights_enterprise_entity) ||
    Insights::Access.enabled_staging?(self.insights_enterprise_entity) ||
    Insights::Access.publish_enabled?(self.insights_enterprise_entity)
  end

  def entity_publish_enabled?
    true
  end

  def should_publish_insights_event?
    !!self.insights_enterprise_entity_id
  end

  def enqueue_instrument_insights_entity_job(topic)
    job_scheduled_at = insights_ingestion_job_enqueued_at
    GitHub.dogstats.increment("insights.monolith.enqueue_ingestion_job", tags: ["topic:#{topic}"])

    return if !insights_enabled? || !entity_publish_enabled?

    GitHub.logger.info(
      "Enqueueing Insights::IncrementalIngestionJob",
      "gh.insights.tenant.id" => self.insights_enterprise_entity_id,
      "gh.insights.entity.name" => self.insights_hydro_entity_name,
      "gh.insights.entity.id" => self.id,
      "gh.job.scheduled_at" => job_scheduled_at)
    Insights::IncrementalIngestionJob.perform_later(topic, insights_entity_name, self.id, job_scheduled_at, entity_updated_at)
  end

  def enqueue_instrument_insights_entity_destroyed_job
    job_scheduled_at = insights_ingestion_job_enqueued_at
    GitHub.dogstats.increment("insights.monolith.enqueue_ingestion_job", tags: ["topic:insights.entity_destroyed"])

    return if !insights_enabled? || !entity_publish_enabled?

    GitHub.logger.info(
      "Enqueueing Insights::EntityDestroyedJob",
      "gh.insights.tenant.id" => self.insights_enterprise_entity_id,
      "gh.insights.entity.name" => self.insights_hydro_entity_name,
      "gh.insights.entity.id" => self.id,
      "gh.job.scheduled_at" => job_scheduled_at)
    Insights::IncrementalIngestion::EntityDestroyedJob.perform_later(
      self.insights_entity_name,
      self.insights_entity_destroyed_job_payload(job_scheduled_at),
      job_scheduled_at)
  end

  def instrument_insights_entity_event(topic, job_scheduled_at)
    if should_publish_insights_event?
      if !self.id_before_type_cast
        GitHub.logger.info(
          "Publishing message with nil entity_id.",
          "messaging.destination.name" => topic,
          "gh.insights.tenant.id" => self.insights_enterprise_entity_id,
          "gh.insights.entity.name" => self.insights_hydro_entity_name)
      end
      GlobalInstrumenter.instrument(topic, insights_entity_activity_payload(job_scheduled_at))
    else
      GitHub.logger.info(
        "Skipping Publishing Insights hydro message.",
        "messaging.destination.name" => topic,
        "gh.insights.tenant.id" => self.insights_enterprise_entity_id,
        "gh.insights.entity.name" => self.insights_hydro_entity_name,
        "gh.insights.entity.id" => self.id)
    end
  end

  def entity_updated_at
    if self.immutable_record? || self.updated_at.nil?
      nil
    else
      self.updated_at_before_type_cast.to_time
    end
  end

  def insights_ingestion_job_enqueued_at
    Time.now.utc
  end

  def insights_entity_name
    self.class.name
  end

  def insights_entity_destroyed_job_payload(job_scheduled_at)
    payload_for_job = self.insights_entity_activity_payload(job_scheduled_at)
    payload_for_job[:message][:data] = payload_for_job[:message][:data].map { |k, v| [k.to_s, v.to_s.dup.force_encoding("utf-8")] }.to_h
    payload_for_job
  end

  def insights_entity_activity_payload(job_scheduled_at)
    payload = {
      message: {
        entity: self.insights_hydro_entity_name,
        data: self.insights_entity_attributes,
        insights_enterprise_entity_id: self.insights_enterprise_entity_id,
        insights_entity_shard_id: self.insights_entity_shard_id
      },
      partition_key: self.insights_hydro_partition_key
    }
    # Adding source_time column to the payload with after_commit trigger time, to be used for calculating the insights latency
    payload[:message][:data][:source_time] = job_scheduled_at.strftime("%Y-%m-%d %H:%M:%S %z")
    payload
  end

  def insights_hydro_entity_name
    self.class.table_name.singularize
  end

  def insights_hydro_partition_key
    "#{self.insights_hydro_entity_name}:#{self.id}"
  end

  def insights_enterprise_entity_id
    self.insights_enterprise_entity.try(:id)
  end

  # NOTE: update this method to insights_formatted_datetime(value) once we cleanup insights_formatted_datetime_publish FF
  def insights_formatted_timestamp(field)
    if Insights::Access.formatted_timestamp_publish_enabled?(self.insights_enterprise_entity)
      value = self.public_send(field)
      return nil unless value
      value.getutc.iso8601
    else
      self.attributes_before_type_cast[field.to_s]
    end
  end

  def insights_enterprise_entity
    raise_not_implemented("insights_enterprise_entity")
  end

  def insights_entity_shard_id
    raise_not_implemented("insights_entity_shard_id")
  end

  def insights_entity_attributes
    raise_not_implemented("insights_entity_attributes")
  end

  def raise_not_implemented(method_name)
    raise NotImplementedError, "The #{method_name} method must be implemented in the class that includes the Insights::EntityInstrumenter module."
  end
end
