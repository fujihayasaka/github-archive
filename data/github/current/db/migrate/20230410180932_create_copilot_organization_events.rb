# typed: true
class CreateCopilotOrganizationEvents < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_organization_events, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint   :organization_id, unsigned: true, null: false, index: { unique: true }, comment: "The organization"
      t.bigint   :user_id, unsigned: true, null: false, index: true, comment: "The user who triggered the event"
      t.string   :event_type, null: false, comment: "The type of event"
      t.text     :event_data, null: false, comment: "The data for the event"
      t.timestamps
    end
  end
end
