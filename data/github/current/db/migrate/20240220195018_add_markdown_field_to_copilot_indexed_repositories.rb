# typed: true

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
class AddMarkdownFieldToCopilotIndexedRepositories < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::Domain::Copilot
  def up
    change_table :copilot_indexed_repositories, bulk: true do |t|
      t.column :markdown_only, :boolean, null: false, default: false
    end
  end

  def down
    change_table :copilot_indexed_repositories, bulk: true do |t|
      t.remove :markdown_only
    end
  end
end
