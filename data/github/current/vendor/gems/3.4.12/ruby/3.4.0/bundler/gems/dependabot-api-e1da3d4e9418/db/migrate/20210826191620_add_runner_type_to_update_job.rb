# frozen_string_literal: true

class AddRunnerTypeToUpdateJob < ActiveRecord::Migration[6.0]
  def change
    add_column :update_jobs, :runner_type, :string, default: "aws"
  end
end
