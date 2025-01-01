# typed: true
class AddGistPurgeIndex < ActiveRecord::Migration[7.1]
  def change
    add_index :gists, [:delete_flag, :updated_at], unique: false, name: "index_on_delete_flag_updated_at"
  end
end
