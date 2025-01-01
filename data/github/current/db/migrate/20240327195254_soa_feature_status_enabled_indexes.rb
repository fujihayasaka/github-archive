# typed: true

# rubocop:disable GitHub/ReferencingColumnsMustBeBigint
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class SoaFeatureStatusEnabledIndexes < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_feature_status_revisions, bulk: true do |t|
      t.index [:repository_id, :secret_scanning_enabled, :next_revision_date_id], name: "index_soa_feature_statuses_ss_on_repo_next_date"
      t.index [:repository_id, :code_scanning_enabled, :next_revision_date_id], name: "index_soa_feature_statuses_cs_on_repo_next_date"
      t.index [:repository_id, :dependabot_alerts_enabled, :next_revision_date_id], name: "index_soa_feature_statuses_da_on_repo_next_date"
    end
  end
end
