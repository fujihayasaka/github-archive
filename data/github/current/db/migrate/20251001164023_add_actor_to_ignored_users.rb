# typed: true
# frozen_string_literal: true

class AddActorToIgnoredUsers < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Usersd)

  def change
    add_column :ignored_users, :actor_id, :bigint, unsigned: true
  end
end
