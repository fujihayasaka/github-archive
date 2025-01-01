# typed: true
class CreateIssueSummaries < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def change
    create_table :issue_summaries, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :issue_id, unsigned: true, null: false
      t.bigint :user_id, unsigned: true, null: false
      t.text :content, null: false
      t.string :state, limit: 36, null: false
      t.timestamps
    end
    add_index :issue_summaries, [:issue_id, :user_id], unique: true
  end
end
