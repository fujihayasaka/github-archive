# frozen_string_literal: true

class DropInfrastructureColumns < ActiveRecord::Migration[6.0]
  def change
    remove_column(
      :update_jobs,
      :infrastructure,
      :string,
      limit: 20,
    )
    remove_column(
      :update_configs,
      :infrastructure,
      :string,
      limit: 20,
    )
  end
end
