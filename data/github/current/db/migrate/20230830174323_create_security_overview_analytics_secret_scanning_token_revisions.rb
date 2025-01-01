# typed: true

# rubocop:disable GitHub/ReferencingColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type
class CreateSecurityOverviewAnalyticsSecretScanningTokenRevisions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityOverviewAnalytics)

  def change
    create_table :soa_secret_scanning_token_revisions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # Foreign keys
      t.integer     :date_id,                                   null: false, unsigned: true
      t.integer     :next_revision_date_id,                     null: false, unsigned: true
      t.bigint      :repository_id,                             null: false, unsigned: true

      # Token filterable fields
      t.bigint      :token_number,                              null: false, unsigned: true
      t.string      :token_type,                                null: false, limit: 64
      t.string      :token_type_provider,                       null: false, limit: 256
      t.string      :token_type_slug,                           null: false, limit: 256
      t.boolean     :token_resolved,                            null: false
      t.column      :token_resolution,                          :tinyint, unsigned: true, null: true

      # Token auditing fields
      t.datetime    :token_created_at,                          null: false, precision: 3
      t.datetime    :token_updated_at,                          null: false, precision: 3
      t.datetime    :token_resolved_at,                         null: true, precision: 3

      # Analytics auditing fields
      t.timestamps

      t.index [:repository_id, :date_id, :token_number], name: "index_soa_secret_scanning_token_revs_on_repo_date_token", unique: true
      t.index [:repository_id, :next_revision_date_id, :date_id], name: "index_soa_secret_scanning_token_revs_on_repo_dates"
    end
  end
end
