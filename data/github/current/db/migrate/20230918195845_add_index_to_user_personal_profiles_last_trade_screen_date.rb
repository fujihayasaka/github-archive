class AddIndexToUserPersonalProfilesLastTradeScreenDate < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    change_table :user_personal_profiles, bulk: true do |t|
      t.index :last_trade_screen_date
    end
  end
end
