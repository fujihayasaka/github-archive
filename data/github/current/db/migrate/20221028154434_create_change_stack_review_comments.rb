# typed: true

class CreateChangeStackReviewComments < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Ballast)

  def change
    create_table :change_stack_review_comments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :stack_id, unsigned: true, null: false
      t.bigint :review_id, unsigned: true, null: false
      t.bigint :user_id, unsigned: true, null: false

      t.column :path, "varbinary(1024)", null: false
      t.integer :position, null: false
      t.integer :line, null: false
      t.integer :side, null: false, default: 0
      t.boolean :blocking, null: false, default: false

      t.mediumblob :body

      t.timestamps null: false
    end
  end
end
