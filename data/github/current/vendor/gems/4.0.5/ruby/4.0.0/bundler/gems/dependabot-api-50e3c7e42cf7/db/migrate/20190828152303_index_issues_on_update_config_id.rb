# frozen_string_literal: true

class IndexIssuesOnUpdateConfigId < ActiveRecord::Migration[6.0]
  def change
    add_index :issues, :update_config_id
  end
end
