# typed: true
class AddClosedAtToDiscussions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    add_column :discussions, :closed_at, :datetime, precision: 6, null: true
  end
end
