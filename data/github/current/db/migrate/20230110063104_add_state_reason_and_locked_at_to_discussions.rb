# typed: true
class AddStateReasonAndLockedAtToDiscussions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    change_table :discussions, bulk: true do |t|
      t.column :state_reason, :integer, limit: 1, null: true
      t.column :locked_at, :datetime, precision: 6, null: true
    end
  end
end
