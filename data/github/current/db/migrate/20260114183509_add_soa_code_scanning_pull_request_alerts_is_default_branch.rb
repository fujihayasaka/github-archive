# typed: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class AddSoaCodeScanningPullRequestAlertsIsDefaultBranch < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_code_scanning_pull_request_alerts, bulk: true do |t|
      t.boolean :is_default_branch, null: false, default: true, after: :alert_updated_at, comment: "Indicates if the alert is on the default branch."
    end
  end
end
