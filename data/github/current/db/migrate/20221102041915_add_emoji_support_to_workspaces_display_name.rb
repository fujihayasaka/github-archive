# typed: true
class AddEmojiSupportToWorkspacesDisplayName < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def up
    change_column :workspaces, :display_name, :string, limit: 48, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
  end

  def down
    change_column :workspaces, :display_name, "varchar(48)"
  end
end
