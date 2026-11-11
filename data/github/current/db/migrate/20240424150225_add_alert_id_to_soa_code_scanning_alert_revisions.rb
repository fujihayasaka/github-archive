# typed: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# rubocop:disable GitHub/ReferencingColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class AddAlertIdToSoaCodeScanningAlertRevisions < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    add_column :soa_code_scanning_alert_revisions, :alert_id, :bigint, unsigned: true, null: false, default: 0, after: :alert_number
  end
end
