class RepositoriesPushesSha256Pushes < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def up
    change_table :pushes, bulk: true do |t|
      t.change :before, :string, limit: 64
      t.change :after, :string, limit: 64
    end
  end

  def down
    change_table :pushes, bulk: true do |t|
      t.change :before, :string, limit: 40
      t.change :after, :string, limit: 40
    end
  end
end
