class AddPackageManagerToConsumer < ActiveRecord::Migration[5.0]
  def change
    add_column :consumers, :package_manager, :integer, null: false

    change_table :consumers do |t|
      t.timestamps
    end
  end
end
