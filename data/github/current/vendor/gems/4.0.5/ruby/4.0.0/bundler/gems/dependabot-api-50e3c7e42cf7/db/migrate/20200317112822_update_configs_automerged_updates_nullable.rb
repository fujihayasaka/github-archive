# frozen_string_literal: true

class UpdateConfigsAutomergedUpdatesNullable < ActiveRecord::Migration[6.0]
  def change
    change_column(:update_configs, :automerged_updates, :text, null: true) # rubocop:disable Rails/ReversibleMigration
  end
end
