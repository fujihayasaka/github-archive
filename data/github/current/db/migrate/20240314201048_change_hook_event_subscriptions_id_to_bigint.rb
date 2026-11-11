class ChangeHookEventSubscriptionsIdToBigint < ActiveRecord::Migration[7.2]
  def up
    change_table :hook_event_subscriptions, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :subscriber_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :hook_event_subscriptions, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :subscriber_id, :int, null: false
    end
  end
end
