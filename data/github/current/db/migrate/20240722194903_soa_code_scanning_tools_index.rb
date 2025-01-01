# typed: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class SoaCodeScanningToolsIndex < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    add_index :soa_code_scanning_alert_revisions,
      [:repository_id, :next_revision_date_id, :alert_severity, :tool],
      unique: false,
      name: "idx_soa_code_scanning_alert_revs_on_repo_next_date_severity_tool"
  end
end
