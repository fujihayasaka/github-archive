# typed: true

# rubocop:disable GitHub/ReferencingColumnsMustBeBigint
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type
class ChangeSoaFeatureStatusRevisionsIndexes < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_feature_status_revisions, bulk: true do |t|
      t.index [:repository_id, :date_id], name: "index_soa_feature_statuses_on_repo_date", unique: true
    end
  end
end
