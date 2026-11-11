# frozen_string_literal: true

class IndexToIgnoreConditionsOnConfigAndFile < ActiveRecord::Migration[7.0]
  def change
    add_index :ignore_conditions, %i(update_config_id from_config_file), name: "index_ignore_conditions_on_config_and_file"
  end
end
