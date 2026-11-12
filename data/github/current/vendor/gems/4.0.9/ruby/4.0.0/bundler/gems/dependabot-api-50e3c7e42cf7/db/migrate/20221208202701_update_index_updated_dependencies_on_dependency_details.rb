# frozen_string_literal: true

class UpdateIndexUpdatedDependenciesOnDependencyDetails < ActiveRecord::Migration[7.0]
  def up
    remove_index(
      :updated_dependencies,
      %i(name package_manager version previous_version),
      name: "index_updated_dependencies_on_dependency_details"
    )

    add_index(
      :updated_dependencies,
      %i(name package_manager version previous_version pull_request_id),
      name: "index_updated_dependencies_on_dependency_details_and_pr_id"
    )
  end

  def down
    remove_index(
      :updated_dependencies,
      %i(name package_manager version previous_version pull_request_id),
      name: "index_updated_dependencies_on_dependency_details_and_pr_id"
    )

    add_index(
      :updated_dependencies,
      %i(name package_manager version previous_version),
      name: "index_updated_dependencies_on_dependency_details"
    )
  end
end
