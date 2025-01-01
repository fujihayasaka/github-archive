# typed: true

class AddIndexesToUserSignups < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :user_signups, bulk: true do |t|
      t.index :created_at
      t.index :updated_at
    end
  end
end
