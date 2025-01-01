# typed: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class RemoveSoaCodeScanningPullRequestAlertsAlertId < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def up
    change_table :soa_code_scanning_pull_request_alerts, bulk: true do |t|
      t.remove :alert_id
    end
  end

  def down
    change_table :soa_code_scanning_pull_request_alerts, bulk: true do |t|
      t.bigint :alert_id, unsigned: true, null: true, after: :alert_number
    end
  end
end
