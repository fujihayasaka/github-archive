# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class AddOwnerOrgIdToVulnerableVersionRangeAlertingProcesses < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Notify)

  def change
    change_table :vulnerable_version_range_alerting_processes, bulk: true do |t|
      t.unsigned_bigint :owner_org_id, null: true, default: nil
    end
  end
end
