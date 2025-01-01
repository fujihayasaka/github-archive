# frozen_string_literal: true

class AddAdvisoryIndexes < ActiveRecord::Migration[5.1]
  def change
    add_index :advisories, :severity
    add_index :advisories, :created_at
    add_index :advisories, :updated_at
  end
end
