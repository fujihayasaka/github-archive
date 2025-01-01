# typed: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class AddSoaDependabotAlertsRevisionsDashboardDatesCoverageIndex < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_dependabot_alert_revisions, bulk: true do |t|
      # This index allows for quick datediff calculation between date_id and alert_created_at or alert_resolved_at dates
      # These calculations are always done with specific values of alert_resolved and alert_resolution, which are also added here
      # `date_id <= 1234` filter can use index, but `next_revision_date_id > 1234` has to be checked in a loop
      # see https://dev.mysql.com/doc/refman/8.0/en/range-optimization.html#range-access-multi-part
      t.index [:repository_id, :alert_resolved, :alert_resolution, :date_id, :next_revision_date_id,  :alert_created_at, :alert_resolved_at], name:  "index_soa_dependabot_alert_revs_on_dashboard_dates_coverage"
    end
  end
end
