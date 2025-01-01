# typed: true
class MakeConcAndOrgNullableGhesJobExecution < ActiveRecord::Migration[7.1]
  def change
    change_table(:ghes_actions_job_executions, bulk: true) do |t|
      t.change :job_check_run_conclusion, :string, limit: 50, null: true
      t.change :organization_id, "BIGINT(20) UNSIGNED", null: true
    end
  end
end
