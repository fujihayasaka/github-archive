# typed: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class AddValidityAndBypassedFieldsToSsRevisions < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)
  def up
    change_table :soa_secret_scanning_alert_revisions, bulk: true do |t|
      t.column :alert_bypassed, :boolean, null: false, default: false, after: :alert_type_slug
      t.column :alert_validity, :tinyint, unsigned: true, null: true, after: :alert_bypassed
      t.column :alert_validity_updated_at, :datetime, precision: 3, after: :alert_reopened_at
    end
  end

  def down
    change_table :soa_secret_scanning_alert_revisions, bulk: true do |t|
      t.remove :alert_bypassed
      t.remove :alert_validity
      t.remove :alert_validity_updated_at
    end
  end
end
