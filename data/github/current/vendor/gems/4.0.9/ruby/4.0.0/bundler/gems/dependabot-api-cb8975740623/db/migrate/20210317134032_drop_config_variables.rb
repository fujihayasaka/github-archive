# frozen_string_literal: true

class DropConfigVariables < ActiveRecord::Migration[6.0]
  def up
    drop_table :config_variables
  end
end
