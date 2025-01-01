class DropRepositories < ActiveRecord::Migration[5.0]
  def change
    drop_table :repositories
  end
end
