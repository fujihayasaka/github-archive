# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class ChangeSecurityOverviewAnalyticsCodeScanningAlertRevisions < ActiveRecord::Migration[7.1]
  use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_column :soa_code_scanning_alert_revisions, :ref, "varbinary(1024)"
  end
end
