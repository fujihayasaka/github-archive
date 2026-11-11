# typed: true

class CreateChangeStackReviews < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Ballast)

  def change
    create_table :change_stack_reviews, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :stack_id, unsigned: true, null: false
      t.bigint :user_id, unsigned: true, null: false
      t.column :change_oid, "char(40)", null: false, limit: 40

      t.integer :state, null: false, default: 0
      t.mediumblob :body

      t.timestamps null: false
    end

    add_index :change_stack_reviews, [:stack_id, :change_oid], name: "by_stack_and_change"
  end
end
