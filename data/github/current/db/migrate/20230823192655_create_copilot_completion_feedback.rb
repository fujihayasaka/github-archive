class CreateCopilotCompletionFeedback < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)


  def change
    create_table :copilot_completion_feedback, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, null: false, unsigned: true
      t.bigint :user_id, null: false, unsigned: true

      t.string :job_id, limit: 55, null: false

      t.integer :sentiment, null: false, default: 0
      t.boolean :contact, null: false, default: false

      t.blob :context, null: false
      t.mediumblob :body

      t.timestamps

      t.index :job_id, unique: true
    end
  end
end
