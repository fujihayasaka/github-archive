# frozen_string_literal: true

class MakeInfrastructureNullable < ActiveRecord::Migration[6.0]
  def change
    change_column_null :update_configs, :infrastructure, true
    change_column_null :update_jobs, :infrastructure, true
  end
end
