# frozen_string_literal: true

class CreateLabels < ActiveRecord::Migration[7.0]
  def change
    create_table :labels do |t|
      t.string :name, limit: 200, null: false, collation: "utf8mb4_unicode_520_ci"
      t.text :description, limit: 400, collation: "utf8mb4_unicode_520_ci"
      t.string :color, limit: 10
      t.timestamps

      t.index :name, unique: true
    end

    create_table :advisory_reviews_labels do |t|
      t.bigint :label_id, null: false
      t.bigint :advisory_review_id, null: false
      t.timestamps

      t.index [:label_id, :advisory_review_id], unique: true, name: "index_on_label_id_and_advisory_review_id"
      t.index :advisory_review_id
    end
  end
end
