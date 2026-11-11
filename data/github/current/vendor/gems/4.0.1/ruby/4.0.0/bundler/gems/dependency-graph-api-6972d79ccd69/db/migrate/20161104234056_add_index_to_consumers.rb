class AddIndexToConsumers < ActiveRecord::Migration[5.0]
  def change
    add_index :consumers, :repository_id
  end
end
