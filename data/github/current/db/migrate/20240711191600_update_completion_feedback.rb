class UpdateCompletionFeedback < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def up
    change_table :copilot_completion_feedback, bulk: true do |t|
      t.change :job_id, :string, limit: 55, null: true
      t.integer :classification, default: 0, null: false, after: :body
      t.string :session_id, limit: 55, null: true, after: :classification

      t.index :session_id
      # remove unique constraint
      t.remove_index :job_id
      t.index :job_id
    end
  end

  def down
    change_table :copilot_completion_feedback, bulk: true do |t|
      t.change :job_id, :string, limit: 55, null: false
      t.remove :classification
      t.remove :session_id

      t.remove_index :session_id
      # add unique constraint
      t.remove_index :job_id
      t.index :job_id, unique: true
    end
  end
end
