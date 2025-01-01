# typed: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class AddSoaCodeScanningPullRequestAlertsAlertResolvedAt < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_code_scanning_pull_request_alerts, bulk: true do |t|
      t.datetime :alert_resolved_at, precision: 3, null: true, after: :alert_updated_at, comment: "The fixed_at or resolved_at timestamp of the alert when the pull request merged."
    end
  end
end
