# typed: true

class CreateCopilotUsageDetails < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_usage_details, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :user,                  null: false, index: true
      t.references :organization,          null: true, index: false
      t.references :repository,            null: true, index: false
      t.text       :remote_repository,     null: true, comment: "The remote repository URL"
      t.string     :request_id,            null: true, limit: 40, comment: "The request ID - used to correlate with datadot"
      t.string     :access_type,           null: true, limit: 40, comment: "The type of access the user has to Copilot"
      t.string     :ip_address,            null: true, limit: 40, comment: "The IP address of the user"
      t.string     :editor_version,        null: true, limit: 40, comment: "The version of the editor used by the user"
      t.string     :editor_plugin_version, null: true, limit: 40, comment: "The version of the editor plugin used by the user"
      t.timestamps
    end
  end
end
