# typed: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class SecurityOverviewAnalyticsSubfeatureStatus < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_feature_status_revisions, bulk: true do |t|
      t.column :dependabot_security_updates_enabled, "tinyint(1)", null: true, after: :dependabot_alerts_enabled
      t.column :code_scanning_pr_alerts_enabled, "tinyint(1)", null: true, after: :code_scanning_enabled
    end
  end
end
