# typed: true

# rubocop:disable GitHub/ReferencingColumnsMustBeBigint
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type
class ModifySoaSecretScanningAlertRevisionsIndexAndColumns < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_secret_scanning_alert_revisions, bulk: true do |t|
      # Change the column order of the index to optimize for upserts
      t.remove_index name: "index_soa_secret_scanning_alert_revs_on_repo_date_alert"
      t.index [:repository_id, :alert_number, :date_id], name: "index_soa_secret_scanning_alert_revs_on_repo_alert_date", unique: true

      # Make new unique index to prevent bad inserts
      t.index [:repository_id, :alert_number, :next_revision_date_id], name: "index_soa_secret_scanning_alert_revs_on_repo_alert_ndate", unique: true
    end
  end
end
