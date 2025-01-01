class CreateCopilotCodingGuidelinePaths < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :copilot_coding_guideline_paths, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :copilot_coding_guideline_id, :bigint, unsigned: true, null: false, index: true
      t.string :path, null: false, limit: 200
      t.timestamps
    end
  end
end
