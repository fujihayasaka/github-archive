class AddLastCheckedAtToGlobalNotices < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    change_table :global_notices, bulk: true do |t|
      t.column :last_checked_at, :datetime, precision: 6, null: true, index: true
    end
  end
end
