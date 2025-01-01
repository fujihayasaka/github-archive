# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class SoaCodeScanningRevisionAlertIdIndex < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_code_scanning_alert_revisions, bulk: true do |t|
      # Index to mirror the existing UQ with `alert_number`.
      # The `alert_id` field is temporary during a data migration/backfill,
      # and this index supports that interim query pattern.
      t.index [:repository_id, :alert_id, :date_id], name: "idx_soa_code_scanning_alert_revs_on_repo_alert_id_date"
    end
  end
end
