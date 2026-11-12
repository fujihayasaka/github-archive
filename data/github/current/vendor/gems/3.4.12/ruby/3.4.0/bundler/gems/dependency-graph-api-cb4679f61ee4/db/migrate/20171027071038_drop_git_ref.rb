class DropGitRef < ActiveRecord::Migration[5.0]
  def up
    if column_exists?(:package_versions, :git_ref)
      remove_column :package_versions, :git_ref, :string
    end
  end

  def down
    unless column_exists?(:package_versions, :git_ref)
      add_column :package_versions, :git_ref, :string
    end
  end
end
