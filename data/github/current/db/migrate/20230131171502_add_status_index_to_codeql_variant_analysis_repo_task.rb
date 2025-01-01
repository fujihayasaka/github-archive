# typed: true
# frozen_string_literal: true

class AddStatusIndexToCodeqlVariantAnalysisRepoTask < ActiveRecord::Migration[7.1]
  def change
    change_table :codeql_variant_analysis_repo_tasks, bulk: true do |t|
      t.index [:status, :created_at], name: "index_codeql_v_a_repo_tasks_on_status_and_created_at"
    end
  end
end
