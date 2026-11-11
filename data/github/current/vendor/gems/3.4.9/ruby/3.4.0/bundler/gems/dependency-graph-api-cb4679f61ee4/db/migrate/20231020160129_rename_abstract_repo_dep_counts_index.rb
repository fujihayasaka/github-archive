class RenameAbstractRepoDepCountsIndex < ActiveRecord::Migration[7.0]
  # fix ancient copypasta here:
  # https://github.com/github/dependency-graph-api/blob/master/db/migrate/20211112182353_normalize_index_names.rb#L19
  def change
    if index_name_exists?(:dg_abstract_repository_dependency_counts, :index_dg_abstract_repository_dependencies_on_repository_id)
      rename_index(
        :dg_abstract_repository_dependency_counts,
        :index_dg_abstract_repository_dependencies_on_repository_id,
        :index_dg_abstract_repository_dependency_counts_on_package_name)
    end
  end
end
