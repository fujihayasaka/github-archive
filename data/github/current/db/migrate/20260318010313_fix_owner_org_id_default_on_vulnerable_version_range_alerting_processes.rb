# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/EnsureDomainIsolationInMigration
# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
#   Disabled because owner_org_id is dropped and recreated as part of this migration,
#   so the unique index is being added to a freshly created column, not an existing one.

class FixOwnerOrgIdDefaultOnVulnerableVersionRangeAlertingProcesses < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Notify)

  # owner_org_id was added in 20260311201207 with null: true, default: nil, and the unique index
  # was expanded to include it in 20260316175615. Since the column is unused (all existing values
  # are NULL), we drop and recreate it as NOT NULL DEFAULT 0 — matching the sentinel approach used
  # by detection_provider — so the unique index correctly enforces uniqueness from the start.
  # In MySQL, NULL != NULL in UNIQUE indexes, so the old nullable column did not enforce uniqueness.
  # Additionally, the new column is renamed to org_id to match the semantics used elsewhere.
  def up
    change_table :vulnerable_version_range_alerting_processes, bulk: true do |t|
      t.remove_index name: :index_vae_id_vvr_id_provider_and_owner,
                     column: [:vulnerability_alerting_event_id, :vulnerable_version_range_id, :detection_provider, :owner_org_id],
                     unique: true
      t.remove :owner_org_id
      t.unsigned_bigint :org_id, null: false, default: 0
      t.index [:vulnerability_alerting_event_id, :vulnerable_version_range_id, :detection_provider, :org_id],
              name: :index_vae_id_vvr_id_provider_and_owner,
              unique: true
    end
  end

  def down
    change_table :vulnerable_version_range_alerting_processes, bulk: true do |t|
      t.remove_index name: :index_vae_id_vvr_id_provider_and_owner,
                     column: [:vulnerability_alerting_event_id, :vulnerable_version_range_id, :detection_provider, :org_id],
                     unique: true
      t.remove :org_id
      t.unsigned_bigint :owner_org_id, null: true, default: nil
      t.index [:vulnerability_alerting_event_id, :vulnerable_version_range_id, :detection_provider, :owner_org_id],
              name: :index_vae_id_vvr_id_provider_and_owner,
              unique: true
    end
  end
end
