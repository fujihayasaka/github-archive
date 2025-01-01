# frozen_string_literal: true

class AddWithdrawnAtToAdvisories < ActiveRecord::Migration[5.1]
  def change
    add_column :advisories, :withdrawn_at, :datetime
    add_index :advisories, :withdrawn_at
  end
end
