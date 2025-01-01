# typed: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class AddScopeAndHasToSecurityOverviewAnalyticsDependabotAlertRevisions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_dependabot_alert_revisions, bulk: true do |t|
      t.boolean :has_patch, null: false
      t.boolean :has_vulnerable_calls, null: false
      t.string  :dependency_scope, null: true, limit: 22
    end
  end
end
