# typed: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is an int type

class SoaDependabotAlertRevisionsAdvisorySlicing < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_dependabot_alert_revisions, bulk: true do |t|
      t.virtual :advisory_slice4, as: "mod(crc32(ghsa_id),4)", type: :tinyint, stored: false
      t.index [:advisory_slice4, :repository_id, :alert_resolved, :alert_severity, :date_id, :next_revision_date_id, :ghsa_id], name: "index_soa_advisory_slice4_da_alert_revs"
    end
  end
end
