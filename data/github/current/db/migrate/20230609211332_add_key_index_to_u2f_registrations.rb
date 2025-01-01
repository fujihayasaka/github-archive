# typed: true

class AddKeyIndexToU2fRegistrations < ActiveRecord::Migration[7.1]
  def change
    change_table :u2f_registrations, bulk: true do |t|
      t.remove_index [:user_id], name: "index_u2f_registrations_on_user_id_and_platform_scope"
      t.index [:key_handle], length: { key_handle: 20 }, name: "index_repositories_on_key_handle"
    end
  end
end
