# frozen_string_literal: true

class RemoveUpdateConfigsAutomergedUpdates < ActiveRecord::Migration[6.0]
  def change
    remove_column :update_configs, :automerged_updates, :text
  end
end
