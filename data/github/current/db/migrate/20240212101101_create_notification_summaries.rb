class CreateNotificationSummaries < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::NotificationsSummaries)

  def change
    create_table :notification_summaries, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :list_type, null: false, limit: 64, default: "Repository"
      t.bigint :list_id, null: false, unsigned: true
      t.blob :raw_data
      t.string :thread_key, null: false, limit: 80

      t.index %i[list_id list_type thread_key], unique: true, name: "unique_notification_summaries_list_id_list_type_thread_key"


      t.timestamps
    end
  end
end
