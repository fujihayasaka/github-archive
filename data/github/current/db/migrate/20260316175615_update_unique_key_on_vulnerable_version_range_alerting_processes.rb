# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/EnsureDomainIsolationInMigration
# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
#   This is skipped as the migration is expanding the unique index to include a fourth column (owner_org_id)
#   which will have a default of NULL on all extant rows.
class UpdateUniqueKeyOnVulnerableVersionRangeAlertingProcesses < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Notify)

  def change
    change_table :vulnerable_version_range_alerting_processes, bulk: true do |t|
      t.remove_index name: :index_vae_id_vvr_id_and_provider,
                     column: [:vulnerability_alerting_event_id, :vulnerable_version_range_id, :detection_provider],
                     unique: true

      t.index [:vulnerability_alerting_event_id, :vulnerable_version_range_id, :detection_provider, :owner_org_id],
              name: :index_vae_id_vvr_id_provider_and_owner,
              unique: true
    end
  end
end
