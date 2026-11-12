class AddBuildDetailsToDgSnapshot < ActiveRecord::Migration[6.0]
  def change
    add_column :dg_snapshots, :build_id, :bigint
    add_column :dg_snapshots, :branch_ref, :string

    add_index :dg_snapshots, [:repository_id, :build_id, :branch_ref], name: "index_dg_snapshots_on_repo_build_id_and_branch_ref"
  end
end
