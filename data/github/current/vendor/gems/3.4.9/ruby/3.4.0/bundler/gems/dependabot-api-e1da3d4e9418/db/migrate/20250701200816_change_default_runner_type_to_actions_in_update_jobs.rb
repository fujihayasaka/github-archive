# frozen_string_literal: true

class ChangeDefaultRunnerTypeToActionsInUpdateJobs < ActiveRecord::Migration[7.0]
  def change
    change_column_default :update_jobs, :runner_type, from: "aws", to: "actions"
  end
end
