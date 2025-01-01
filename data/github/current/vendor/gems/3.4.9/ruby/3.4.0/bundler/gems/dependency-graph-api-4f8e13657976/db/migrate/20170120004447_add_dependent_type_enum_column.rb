class AddDependentTypeEnumColumn < ActiveRecord::Migration[5.0]
  def change
    add_column :dependency_specifications, :dependent_type_id, :integer
  end
end
