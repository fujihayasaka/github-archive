class RevertTimestampChanges < ActiveRecord::Migration[6.0]
  def change
    change_table :dg_packages do |t|
      t.change :last_published_at, :datetime
    end

    change_table :dg_package_versions do |t|
      t.change :published_at, :datetime
      t.change :unpublished_at, :datetime
      t.change :pushed_at, :datetime
    end
  end
end
