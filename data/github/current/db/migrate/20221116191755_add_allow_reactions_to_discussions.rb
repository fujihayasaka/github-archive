# typed: true

class AddAllowReactionsToDiscussions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    add_column :discussions, :allow_reactions, :boolean, default: true, null: false
  end
end
