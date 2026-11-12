# frozen_string_literal: true

class AddUpdateConfigIdColumnToIssues < ActiveRecord::Migration[6.0]
  def change
    add_column :issues, :update_config_id, :bigint
  end
end
