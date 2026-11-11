# typed: false
# frozen_string_literal: true

module Insights::OrganizationInstrumenter
  extend ActiveSupport::Concern

  def insights_ingestion_enabled?
    Insights::Access.enabled?(self.insights_enterprise_entity) ||
      Insights::Access.enabled_staging?(self.insights_enterprise_entity) ||
      Insights::Access.publish_enabled?(self.insights_enterprise_entity)
  end

  def enqueue_instrument_insights_entity_job(topic, user)
    job_scheduled_at = insights_ingestion_job_enqueued_at
    GitHub.dogstats.increment("insights.monolith.enqueue_ingestion_job", tags: ["topic:#{topic}"])

    return if !insights_ingestion_enabled? || !entity_publish_enabled?

    GitHub.logger.info(
      "Enqueueing Insights::IncrementalIngestionJob",
      "gh.insights.tenant.id" => self.insights_enterprise_entity_id,
      "gh.insights.entity.name" => self.insights_hydro_entity_name,
      "gh.insights.entity.id" => self.id,
      "gh.job.scheduled_at" => job_scheduled_at)
    Insights::IncrementalIngestionJob.perform_later(topic, insights_entity_name, user.id, job_scheduled_at, entity_updated_at(user), self)
  end

  def enqueue_instrument_insights_entity_destroyed_job(user)
    job_scheduled_at = insights_ingestion_job_enqueued_at
    GitHub.dogstats.increment("insights.monolith.enqueue_ingestion_job", tags: ["topic:insights.entity_destroyed"])

    return if !insights_ingestion_enabled? || !entity_publish_enabled?

    GitHub.logger.info(
      "Enqueueing Insights::IncrementalIngestion::EntityDestroyedJob",
      "gh.insights.tenant.id" => self.insights_enterprise_entity_id,
      "gh.insights.entity.name" => self.insights_hydro_entity_name,
      "gh.insights.entity.id" => self.id,
      "gh.job.scheduled_at" => job_scheduled_at)
    Insights::IncrementalIngestion::EntityDestroyedJob.perform_later(
      self.insights_entity_name,
      self.insights_entity_destroyed_job_payload(user, job_scheduled_at),
      job_scheduled_at)
  end

  def instrument_insights_entity_event(topic, user, job_scheduled_at)
    if should_publish_insights_event?
      if !user.id_before_type_cast
        GitHub.logger.info(
          "Publishing message with nil entity_id.",
          "messaging.destination.name" => topic,
          "gh.insights.tenant.id" => self.insights_enterprise_entity_id,
          "gh.insights.entity.name" => self.insights_hydro_entity_name)
      end
      GlobalInstrumenter.instrument(topic, insights_entity_activity_payload(user, job_scheduled_at))
    else
      GitHub.logger.info(
        "Skipping Publishing Insights hydro message.",
        "messaging.destination.name" => topic,
        "gh.insights.tenant.id" => self.insights_enterprise_entity_id,
        "gh.insights.entity.name" => self.insights_hydro_entity_name,
        "gh.insights.entity.id" => self.id)
    end
  end

  def insights_entity_destroyed_job_payload(user, job_scheduled_at)
    payload_for_job = self.insights_entity_activity_payload(user, job_scheduled_at)
    payload_for_job[:message][:data] = payload_for_job[:message][:data].map { |k, v| [k.to_s, v.to_s.dup.force_encoding("utf-8")] }.to_h
    payload_for_job
  end

  def insights_entity_activity_payload(user, job_scheduled_at)
    payload = {
      message: {
        entity: self.insights_hydro_entity_name,
        data: self.insights_entity_attributes(user),
        insights_enterprise_entity_id: self.insights_enterprise_entity_id,
        insights_entity_shard_id: self.insights_entity_shard_id
      },
      partition_key: self.insights_hydro_partition_key(user)
    }
    # Adding source_time column to the payload to be used for calculating the insights latency
    payload[:message][:data][:source_time] = job_scheduled_at.strftime("%Y-%m-%d %H:%M:%S %z")
    payload
  end

  def insights_hydro_partition_key(user)
    "#{self.insights_hydro_entity_name}:#{user.id}"
  end

  def should_publish_insights_event?
    !!self.insights_enterprise_entity_id
  end

  def entity_publish_enabled?
    Insights::Access.users_publish_enabled?(self.insights_enterprise_entity)
  end

  def entity_updated_at(user)
    user.updated_at_before_type_cast.to_time
  end

  def insights_ingestion_job_enqueued_at
    Time.now.utc
  end

  def insights_hydro_entity_name
    self.class.table_name.singularize
  end

  def insights_enterprise_entity_id
    self.insights_enterprise_entity.try(:id)
  end

  def insights_enterprise_entity
    self
  end

  def insights_entity_shard_id
    self.id
  end

  def insights_entity_name
    "User"
  end

  # NOTE: update this method to insights_formatted_datetime(value) once we cleanup insights_formatted_datetime_publish FF
  def insights_formatted_timestamp(field, user)
    value = user.public_send(field)

    if Insights::Access.formatted_timestamp_publish_enabled?(self.insights_enterprise_entity)
      return nil unless value
      value.getutc.iso8601
    else
      user.attributes_before_type_cast[field.to_s]
    end
  end

  def insights_entity_attributes(user)
    {
      id: user.id_before_type_cast,
      login: user.login_before_type_cast,
      disabled:  user.disabled_before_type_cast,
      spammy: user.spammy_before_type_cast,
      type: user.type_before_type_cast,
      suspended_at: insights_formatted_timestamp(:suspended_at, user),
      organization_billing_email: user.organization_billing_email_before_type_cast,
      time_zone_name: user.time_zone_name_before_type_cast,
      spammy_reason: user.spammy_reason_before_type_cast,
      primary_language_name_id: user.primary_language_name_id_before_type_cast,
      created_at: insights_formatted_timestamp(:created_at, user),
      updated_at: insights_formatted_timestamp(:updated_at, user)
    }
  end
end
