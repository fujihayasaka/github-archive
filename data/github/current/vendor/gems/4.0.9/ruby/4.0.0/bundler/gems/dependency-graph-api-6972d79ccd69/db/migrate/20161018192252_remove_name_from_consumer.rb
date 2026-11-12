class RemoveNameFromConsumer < ActiveRecord::Migration[5.0]
  def change
    remove_column :consumers, :name, :string
  end
end
