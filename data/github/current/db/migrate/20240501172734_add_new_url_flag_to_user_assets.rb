class AddNewUrlFlagToUserAssets < ActiveRecord::Migration[7.2]
  def change
    change_table :user_assets, bulk: true do |t|
      t.column :using_new_url, :boolean, null: true, default: nil
    end
  end
end
