# frozen_string_literal: true

class CreateAdvisorySyncState < ActiveRecord::Migration[6.1]
  def change
    create_table :advisory_sync_states do |t|
      t.integer :advisory_id
      t.datetime :processed_at
      t.datetime :pushed_at
      t.timestamps
      t.index :advisory_id, unique: true
    end
  end
end
