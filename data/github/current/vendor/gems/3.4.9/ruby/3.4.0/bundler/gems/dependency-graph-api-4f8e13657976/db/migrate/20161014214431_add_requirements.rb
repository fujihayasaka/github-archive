class AddRequirements < ActiveRecord::Migration[5.0]
  def change
    rename_column :dependency_specifications, :version_specification, :requirements
    add_column :dependency_specifications, :encoded_lower_bound, :bigint
    add_column :dependency_specifications, :encoded_upper_bound, :bigint
  end
end
