# frozen_string_literal: true

class AddAutomergeFeatureFlag < ActiveRecord::Migration[6.0]
  def change
    add_column :accounts, :allow_automerging, :boolean
  end
end
