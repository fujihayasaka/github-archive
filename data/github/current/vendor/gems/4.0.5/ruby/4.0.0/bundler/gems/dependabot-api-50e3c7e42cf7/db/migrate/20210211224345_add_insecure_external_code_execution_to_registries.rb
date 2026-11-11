# frozen_string_literal: true

class AddInsecureExternalCodeExecutionToRegistries < ActiveRecord::Migration[6.0]
  def change
    add_column :registries, :insecure_external_code_execution, "enum('allow', 'deny')"
  end
end
