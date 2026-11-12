# frozen_string_literal: true

class AddInfrastructureFlags < ActiveRecord::Migration[6.0]
  def change
    add_column :update_jobs, :infrastructure, :string
    add_column :update_configs, :infrastructure, :string
  end
end
