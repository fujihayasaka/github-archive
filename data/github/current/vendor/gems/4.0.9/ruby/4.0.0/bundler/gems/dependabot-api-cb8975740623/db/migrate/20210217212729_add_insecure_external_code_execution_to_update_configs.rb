# frozen_string_literal: true

class AddInsecureExternalCodeExecutionToUpdateConfigs < ActiveRecord::Migration[6.0]
  def change
    add_column :update_configs, :insecure_external_code_execution, "enum('allow', 'deny')"
  end
end
