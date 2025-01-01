# typed: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class SoaSliceSsRevisions < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_secret_scanning_alert_revisions, bulk: true do |t|
      t.virtual :slice4, as: "mod(floor(updated_at),4)", type: :tinyint, stored: false
      t.index [:slice4, :repository_id, :alert_resolved, :alert_resolution, :date_id, :next_revision_date_id,  :alert_created_at, :alert_resolved_at, :alert_reopened_at], name:  "index_soa_slice4_ss_alert_revs_on_dashboard_dates_coverage"
    end
  end
end
