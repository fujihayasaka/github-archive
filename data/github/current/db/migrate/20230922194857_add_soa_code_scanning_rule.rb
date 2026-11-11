# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The table references soa_dates.id, which is int type. We know the domain of the value; it is not auto increment.
# This is a storage optimization for projected growth.

class AddSoaCodeScanningRule < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def up
    change_table :soa_code_scanning_alert_revisions, bulk: true do |t|
      t.column :rule_sarif_identifier, "varchar(255)", null: false, after: :tool

      t.remove_index name: "index_soa_code_scanning_alert_revs_on_repo_date_alert"
      t.index [:repository_id, :alert_number, :date_id], name: "idx_soa_code_scanning_alert_revs_on_repo_alert_date", unique: true
      t.index [:repository_id, :alert_number, :next_revision_date_id], name: "idx_soa_code_scanning_alert_revs_on_repo_alert_next_date", unique: true
    end
  end

  def down
    change_table :soa_code_scanning_alert_revisions, bulk: true do |t|
      t.remove_column :rule_sarif_identifier

      t.index [:repository_id, :date_id, :alert_number], name: "index_soa_code_scanning_alert_revs_on_repo_date_alert", unique: true
      t.remove_index name: "idx_soa_code_scanning_alert_revs_on_repo_alert_date"
      t.remove_index name: "idx_soa_code_scanning_alert_revs_on_repo_alert_next_date"
    end
  end
end
