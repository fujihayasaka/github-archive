# typed: true
#frozen_string_literal: true

class AuditLogSettings < ApplicationRecord::Collab
  CURATOR_RETENTION_MONTHS_SETTING = "curator_retention".freeze
  GIT_EVENTS = "git_events".freeze
  include Instrumentation::Model

  belongs_to :business

  after_create_commit :instrument_create
  after_update_commit :instrument_update

  def self.retention_months
    business = GitHub.global_business

    curator_retention_months = find_by(business: business, name: CURATOR_RETENTION_MONTHS_SETTING)

    curator_retention_months ||= new(business: business, name: CURATOR_RETENTION_MONTHS_SETTING, value: "inf")

    curator_retention_months
  end

  def self.git_events
    business = GitHub.global_business

    git_events = find_by(business: business, name: GIT_EVENTS)

    git_events ||= new(business: business, name: GIT_EVENTS, value: "false")

    git_events
  end

  def self.git_events_enabled?
    git_events.value == "true"
  end

  def event_payload
    {
      business: business,
      name: name,
      value: value,
    }
  end

  def instrument_update
    instrument :audit_log_settings_update
  end

  def instrument_create
    instrument :audit_log_settings_create
  end

  def event_prefix
    T.must(business).event_prefix
  end
end
