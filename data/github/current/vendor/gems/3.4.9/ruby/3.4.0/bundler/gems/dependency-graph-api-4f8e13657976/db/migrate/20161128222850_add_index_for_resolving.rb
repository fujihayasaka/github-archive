class AddIndexForResolving < ActiveRecord::Migration[5.0]
  def up
    add_index(
      :dependency_specifications,
      [:resolved_to_id, :depends_on_id, :encoded_lower_bound, :encoded_upper_bound],
      name: "index_dep_spec_resolution"
    )
    remove_index :dependency_specifications, :resolved_to_id
  end

  def down
    add_index :dependency_specifications, :resolved_to_id
    remove_index :dependency_specifications, "index_dep_spec_resolution"
  end
end
