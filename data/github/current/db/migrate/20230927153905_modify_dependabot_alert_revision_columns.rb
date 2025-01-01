# typed: true

# rubocop:disable GitHub/ReferencingColumnsMustBeBigint
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type
class ModifyDependabotAlertRevisionColumns < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def up
    change_table :soa_dependabot_alert_revisions, bulk: true do |t|
      t.change :has_patch, :boolean, null: true
      t.change :has_vulnerable_calls, :boolean, null: true
      t.remove :alert_resolution

      # Change the column order of the index to optimize for upserts
      t.remove_index name: "index_soa_dependabot_alert_revs_on_repo_date_alert"
      t.index [:repository_id, :alert_number, :date_id], name: "index_soa_dependabot_alert_revs_on_repo_alert_date", unique: true

      # Make new unique index to prevent bad inserts
      t.index [:repository_id, :alert_number, :next_revision_date_id], name: "index_soa_dependabot_alert_revs_on_repo_alert_ndate", unique: true
    end
  end

  def down
    change_table :soa_dependabot_alert_revisions, bulk: true do |t|
      t.column :alert_resolution, :tinyint, unsigned: true, null: true, after: :alert_resolved
      t.change :has_patch, :boolean, null: false
      t.change :has_vulnerable_calls, :boolean, null: false

      t.remove_index name: "index_soa_dependabot_alert_revs_on_repo_alert_ndate"
      t.remove_index name: "index_soa_dependabot_alert_revs_on_repo_alert_date"
      t.index [:repository_id, :date_id, :alert_number], name: "index_soa_dependabot_alert_revs_on_repo_date_alert", unique: true
    end
  end
end
