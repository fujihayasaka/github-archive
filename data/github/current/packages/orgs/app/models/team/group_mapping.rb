# typed: true
# frozen_string_literal: true

class Team::GroupMapping < ApplicationRecord::Notify
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations
  include Instrumentation::Model
  attr_accessor :actor

  self.table_name = "team_group_mappings"

  after_create_commit :audit_log_create
  after_destroy_commit :audit_log_destroy

  # The maximum number of Groups that can be mapped to a given Team.
  MAX_GROUP_MAPPINGS_LIMIT = 5

  belongs_to :team, foreign_key: "team_id", class_name: "Team", inverse_of: :group_mappings
  belongs_to :tenant, foreign_key: "tenant_id", class_name: "TeamSync::Tenant", inverse_of: :team_group_mappings

  before_validation :set_tenant, on: :create

  validates :group_id, presence: true, length: { maximum: 40 }
  validates :group_id, unicode3: true, allow_blank: false
  validates :group_name, presence: true
  validates :team, presence: true
  validates :tenant, presence: true

  extend GitHub::Encoding
  force_utf8_encoding :group_name
  force_utf8_encoding :group_description

  STATUS_MAP = {
    "unknown" => :MAPPINGSTATUSUNKNOWN,
    "unsynced" => :UNSYNCED,
    "pending" => :SYNCPENDING,
    "synced" => :SYNCED,
    "disabled" => :SYNCDISABLED,
    "failed" => :SYNCFAILED,
    "partial" => :PARTIAL,
    "retry" => :RETRY,
    "updated" => :UPDATED,
  }

  enum :status, {
    unsynced: 1,
    pending: 2,
    synced: 3,
    disabled: 4,
    failed: 5,
    partial: 6,
    updated: 7,
    retry: 8,
  }

  def self.batch_update_mappings(team, group_mappings, actor:)
    selected_group_ids = group_mappings.map { |attrs| attrs[:group_id] }

    to_add = to_remove = existing_group_ids = T.let(nil, T.untyped)

    transaction do
      existing_group_ids = team.group_mappings.any? ? team.group_mappings.map(&:group_id) : []

      to_add = selected_group_ids - existing_group_ids
      to_remove = existing_group_ids - selected_group_ids

      selected_groups_by_group_id = group_mappings.index_by { |attrs| attrs[:group_id] }

      # groups to remove
      team.group_mappings.where(group_id: to_remove).each do |mapping|
        mapping.actor = actor
        mapping.destroy
      end

      to_add.each do |group_id|
        attrs = selected_groups_by_group_id[group_id].dup
        team.group_mappings.create(attrs.merge(actor: actor))
      end
    end

    if to_add.any? || to_remove.any?
      team.reload

      GitHub.instrument "team_group_mapping.update",
        actor: actor,
        team: team,
        org: team.organization
      GlobalInstrumenter.instrument "team_group_mapping.update",
        actor: actor,
        team: team,
        organization: team.organization,
        team_sync_tenant: team.organization.team_sync_tenant,
        current_mappings: team.group_mappings,
        previous_group_ids: existing_group_ids
    end

    UpdateTeamGroupMappingsJob.perform_later(team)

    team.group_mappings
  end

  private

  def event_prefix
    :team_group_mapping
  end

  def event_payload
    {
      team: team,
      team_id: team_id,
      org: team&.organization,
      group_name: group_name,
      actor: actor,
    }
  end

  def audit_log_create
    instrument :create
  end

  def audit_log_destroy
    instrument :destroy
  end

  # Private: Callback to set the `tenant` association on creation if unset.
  def set_tenant
    self.tenant ||= T.unsafe(team&.organization).team_sync_tenant
  end
end
