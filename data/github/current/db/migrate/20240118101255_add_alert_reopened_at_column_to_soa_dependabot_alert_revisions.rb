# typed: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class AddAlertReopenedAtColumnToSoaDependabotAlertRevisions < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)
  def change
    add_column(:soa_dependabot_alert_revisions, :alert_reopened_at, :datetime, precision: 3, after: :alert_resolved_at)
  end
end
