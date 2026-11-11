# typed: true
# frozen_string_literal: true

class UpdateIgnoredUsersNoteTo250Characters < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Usersd)

  def up
    change_column :ignored_users, :note, :string, limit: 250, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
  end

  def down
    change_column :ignored_users, :note, :string, limit: 100, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
  end
end
