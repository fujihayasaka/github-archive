# typed: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class PrepareSoaCodeScanningPullRequestAlertsAlertIdForRemoval < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def up
    change_table :soa_code_scanning_pull_request_alerts, bulk: true do |t|
      t.change :alert_id, :bigint, unsigned: true, null: true
    end
  end

  def down
    change_table :soa_code_scanning_pull_request_alerts, bulk: true do |t|
      t.change :alert_id, :bigint, unsigned: true, null: false
    end
  end
end
