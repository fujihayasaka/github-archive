# typed: true
# rubocop:disable GitHub/ReferencingColumnsMustBeBigint
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type
class ChangeSoaDependabotAlertRevisionAddReasonGhsa < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def up
    change_table :soa_dependabot_alert_revisions, bulk: true do |t|
      t.remove :has_patch
      t.remove :has_vulnerable_calls

      t.column :alert_resolution, :tinyint, unsigned: true, null: true, after: :alert_resolved
      t.column :ghsa_id, "varchar(19)", null: true, after: :alert_severity
    end
  end

  def down
    change_table :soa_dependabot_alert_revisions, bulk: true do |t|
      t.column :has_patch, :boolean, null: true
      t.column :has_vulnerable_calls, :boolean, null: true

      t.remove :alert_resolution
      t.remove :ghsa_id
    end
  end
end
