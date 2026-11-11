class RemoveResolvedToId < ActiveRecord::Migration[5.0]
  def up
    remove_index :dependency_specifications, name: :index_dep_spec_resolution
    remove_column :dependency_specifications, :resolved_to_id
  end

  def down
    remove_column :dependency_specifications, :resolved_to_id, :integer
    add_index(
      :dependency_specifications,
      [:resolved_to_id, :depends_on_id, :encoded_lower_bound, :encoded_upper_bound],
      name: "index_dep_spec_resolution"
    )
  end
end
