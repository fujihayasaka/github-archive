class CreateReachabilityAnalysis < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def change
    create_table :reachability_analyses, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint  :repository_id,   unsigned: true, null: false
      t.bigint  :workflow_run_id, unsigned: true, null: true

      t.string :sha, limit: 40, null: false

      t.column :state, :tinyint, unsigned: true, default: 0

      t.boolean :missing_data, null: false, default: false

      t.datetime  :enqueued_at,             null: true, precision: 6
      t.datetime  :started_at,              null: true, precision: 6
      t.datetime  :completed_at,            null: true, precision: 6
      t.datetime  :last_status_update_at,   null: true, precision: 6
      t.datetime  :dependabot_notified_at,  null: true, precision: 6

      t.timestamps

      t.index [:repository_id, :sha], name: "index_reachability_analyses_on_repository_id_sha"
      t.index [:repository_id, :state], name: "index_reachability_analyses_on_repository_id_state"
    end
  end
end
