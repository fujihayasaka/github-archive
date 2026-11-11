# frozen_string_literal: true

class IndexUpdatedDependenciesOnDependencyDetailsAndPrId < ActiveRecord::Migration[6.0]
  def up
    remove_index :updated_dependencies, :pull_request_id

    add_index(
      :updated_dependencies,
      %i(pull_request_id name package_manager version previous_version),
      name: "index_updated_dependencies_on_pr_id_and_dependency_details"
    )
  end

  def down
    remove_index(
      :updated_dependencies,
      name: "index_updated_dependencies_on_pr_id_and_dependency_details"
    )

    add_index :updated_dependencies, :pull_request_id
  end
end
