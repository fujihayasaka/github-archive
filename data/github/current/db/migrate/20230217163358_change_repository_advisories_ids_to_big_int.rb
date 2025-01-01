# typed: true
class ChangeRepositoryAdvisoriesIdsToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def up
    change_table :repository_advisories, bulk: true do |t|
      t.change :repository_id, :bigint, unsigned: true, null: false
      t.change :author_id, :bigint, unsigned: true, null: false
      t.change :publisher_id, :bigint, unsigned: true, null: true
      t.change :assignee_id, :bigint, unsigned: true, null: true
      t.change :workspace_repository_id, :bigint, unsigned: true, null: true
      t.change :owner_id, :bigint, unsigned: true, null: true
    end
  end

  def down
    change_table :repository_advisories, bulk: true do |t|
      t.change :repository_id, :integer, null: false
      t.change :author_id, :integer, null: false
      t.change :publisher_id, :integer, null: true
      t.change :assignee_id, :integer, null: true
      t.change :workspace_repository_id, :integer, null: true
      t.change :owner_id, :integer, null: true
    end
  end
end
