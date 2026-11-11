class AddLastUsedAtToU2fRegistrations < ActiveRecord::Migration[7.2]
  def change
    add_column :u2f_registrations, :last_used_at, :datetime, precision: nil, null: true
  end
end
