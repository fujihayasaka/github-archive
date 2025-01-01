# typed: true
class CreateAuditLogAsyncQueries < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    create_table :audit_log_async_queries, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint    :actor_id,      unsigned: true, null: false
      t.column    :actor_type,    "enum('User')", default: "User", null: false
      t.boolean   :completed,     null: false, default: false
      t.column    :query_id,      :string, null: false, limit: 255, index: { unique: true }
      t.column    :operation_id,  :string, null: false, limit: 255, index: { unique: true }

      t.timestamps
    end

    add_index :audit_log_async_queries, [:actor_id, :completed, :created_at], name: "index_al_async_queries_on_actor_id_and_completed_and_created_at"
  end
end
