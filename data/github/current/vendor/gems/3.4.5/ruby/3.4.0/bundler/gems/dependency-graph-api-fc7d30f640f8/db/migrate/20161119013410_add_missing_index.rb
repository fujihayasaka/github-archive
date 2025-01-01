class AddMissingIndex < ActiveRecord::Migration[5.0]
  def change
    add_index :dependency_specifications, :package_name
  end
end
