# typed: true

class CreateAuditLogWebExports < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    create_table :audit_log_web_exports, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint    :actor_id,      unsigned: true, null: false
      t.bigint    :subject_id,    unsigned: true, null: false
      t.column    :subject_type,  "enum('User', 'Organization', 'Business')", default: "User", null: false
      t.column    :format_type,   "enum('json', 'csv')", default: "json", null: false
      t.column    :export_id,     :string, null: false, limit: 255, index: { unique: true }
      t.column    :phrase,        :string, limit: 1024

      t.timestamps
    end

    add_index :audit_log_web_exports, [:subject_id, :subject_type]
    add_index :audit_log_web_exports, [:actor_id]
  end
end
