# typed: true

class SecretScanningJobGroupsCustomPatternId < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up
    change_table(:secret_scanning_job_groups, bulk: true) do |t|
      t.column :data_custom_pattern_id, "BIGINT UNSIGNED GENERATED ALWAYS AS (NULLIF(CAST(json_extract(LOWER(data), '$.custompatternid') AS UNSIGNED),0)) VIRTUAL NULL"
      t.index [:data_custom_pattern_id, :type, :status, :owner_scope_id], name: "secret_scanning_repos_data_custom_pattern_id"
    end
  end

  def down
    change_table(:secret_scanning_job_groups, bulk: true) do |t|
      t.remove_index name: "secret_scanning_repos_data_custom_pattern_id"
      t.remove :data_custom_pattern_id
    end
  end
end
