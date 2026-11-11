# typed: true

class AddIndexToGistsOnUserIdAndPublicAndActiveFields < ActiveRecord::Migration[7.1]
  def change
    change_table :gists, bulk: true do |t|
      t.index [:user_id, :public, :delete_flag, :user_hidden, :disabled_at], name: :index_gists_on_user_id_and_public_and_active_fields
      t.remove_index [:user_id, :public, :delete_flag, :user_hidden], name: :index_gists_on_user_id_and_public_and_delete_flg_and_user_hidden
    end
  end
end
