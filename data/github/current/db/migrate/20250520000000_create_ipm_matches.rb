# typed: true

class CreateIpmMatches < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::InProductTargeting)

  def change
    create_table :ipm_matches, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :user_id, :bigint, unsigned: true, null: false
      t.string :cohort, null: false, limit: 100
      t.json :metadata, null: false
      t.string :day, null: false, limit: 100

      t.timestamps
    end
  end
end
