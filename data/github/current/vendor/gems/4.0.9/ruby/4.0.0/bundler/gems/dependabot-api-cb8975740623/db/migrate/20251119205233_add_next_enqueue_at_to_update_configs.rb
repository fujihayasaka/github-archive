# frozen_string_literal: true

class AddNextEnqueueAtToUpdateConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :update_configs, :next_enqueue_at, :datetime
    add_index :update_configs, :next_enqueue_at
  end
end
