# frozen_string_literal: true

class MakeInfrastructureNonNullable < ActiveRecord::Migration[6.0]
  def change
    change_column_null :update_jobs, :infrastructure, false
    change_column_null :update_configs, :infrastructure, false
  end
end
