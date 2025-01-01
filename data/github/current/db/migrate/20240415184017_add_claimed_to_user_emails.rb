class AddClaimedToUserEmails < ActiveRecord::Migration[7.2]
  def up
    change_table :user_emails, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :user_id, :bigint, unsigned: true
      t.boolean :claimed, null: false, default: false
    end
  end

  def down
    change_table :user_emails, bulk: true do |t|
      t.change :id, :int
      t.change :user_id, :int
      t.remove :claimed
    end
  end
end
