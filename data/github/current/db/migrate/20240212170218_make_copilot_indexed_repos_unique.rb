# typed: true
# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
class MakeCopilotIndexedReposUnique < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::Domain::Copilot
  def up
    change_table(:copilot_indexed_repositories, bulk: true) do |t|
      t.remove_index [:repository_id]
      t.index [:repository_id], unique: true
    end
  end

  def down
    change_table(:copilot_indexed_repositories, bulk: true) do |t|
      t.remove_index [:repository_id]
      t.index [:repository_id], unique: false
    end
  end
end
