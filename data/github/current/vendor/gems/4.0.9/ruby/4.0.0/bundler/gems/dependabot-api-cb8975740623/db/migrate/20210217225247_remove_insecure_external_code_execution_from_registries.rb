# frozen_string_literal: true

class RemoveInsecureExternalCodeExecutionFromRegistries < ActiveRecord::Migration[6.0]
  def change
    remove_column :registries, :insecure_external_code_execution, "enum('allow', 'deny')"
  end
end
