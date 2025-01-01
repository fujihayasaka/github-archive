# typed: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class SoaAddAutoCodeqlEligible < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_feature_status_revisions, bulk: true do |t|
      t.column :code_scanning_auto_codeql_eligible, "tinyint(1)", null: true, after: :code_scanning_auto_codeql_enabled
    end
  end
end
