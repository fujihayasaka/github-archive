# typed: true

class UpdateBlockUserNoteSupportEmoji < ActiveRecord::Migration[7.1]
  def up
    change_column :ignored_users, :note, :string, limit: 100, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
  end

  def down
    change_column :ignored_users, :note, :string, limit: 100, charset: "utf8", collation: "utf8_general_ci"
  end
end
