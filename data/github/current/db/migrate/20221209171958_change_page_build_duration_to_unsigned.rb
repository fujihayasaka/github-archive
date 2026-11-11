# typed: true

class ChangePageBuildDurationToUnsigned < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    change_column(:page_builds, :duration, "bigint(20) unsigned")
  end

  def down
    change_column(:page_builds, :duration, "int(11)")
  end
end
