# frozen_string_literal: true

class DropGitHubPlanTransitions < ActiveRecord::Migration[6.0]
  def up
    drop_table :github_plan_transitions
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "github_plan_transitions table has been deleted"
  end
end
