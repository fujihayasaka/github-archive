# frozen_string_literal: true

class CreateImports < ActiveRecord::Migration[5.2]
  def change
    create_table :imports do |t|
      t.integer :source, null: false
      t.string :slack_message_ts
      t.datetime :started_at
      t.integer :total_count
      t.integer :created_count, default: 0, null: false
      t.integer :updated_count, default: 0, null: false
      t.integer :errored_count, default: 0, null: false
      t.datetime :finished_at
      t.timestamps

      t.index [:source, :finished_at]
    end
  end
end
