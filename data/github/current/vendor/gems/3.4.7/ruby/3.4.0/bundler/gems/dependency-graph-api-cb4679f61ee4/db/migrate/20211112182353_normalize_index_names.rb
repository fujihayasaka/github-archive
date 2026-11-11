class NormalizeIndexNames < ActiveRecord::Migration[6.0]
  def change
    # step 1: sync local index names with prod DB index names, favoring prod
    # to avoid lengthy prod migrations with Skeefree
    [
      {
        table: "dg_abstract_repository_dependencies",
        old: "index_abstract_repository_dependencies_on_repository_id",
        new: "index_dg_abstract_repository_dependencies_on_repository_id"
      },
      {
        table: "dg_abstract_repository_dependencies",
        old: "abstract_repo_dep_lookups",
        new: "index_abstract_repo_dep_lookups"
      },
      {
        table: "dg_abstract_repository_dependency_counts",
        old: "index_abstract_repository_dependency_counts_on_package_name",
        new: "index_dg_abstract_repository_dependencies_on_repository_id"
      },
    ].each do |entry|
      # Updated to address: https://github.com/github/ghes/issues/3072
      if index_name_exists?(entry[:table], entry[:old])
        execute "ALTER TABLE #{entry[:table]} RENAME INDEX #{entry[:old]} TO #{entry[:new]}"
      end
    end

    # Updated to address: https://github.com/github/ghes/issues/3072
    # step 2: add missing index found in prod RW DB to local schema!
    add_index :dg_transitive_package_dependencies, [:package_id, :dependency_id], name: :index_dg_transitive_package_dependencies_unique, unique: true, if_not_exists: true
  end
end
