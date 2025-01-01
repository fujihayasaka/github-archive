# typed: false

class AddFrozenDescriptionTitleToRepositoryAdvisories < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def self.up
    change_table :repository_advisories, bulk: true do |t|
      t.column :frozen_description, :mediumblob, null: true, comment: "The description of the advisory when the author was removed as a collaborator. Only populated at removal time."
      t.column :frozen_title, "varbinary(1024)", null: true, comment: "The title of the advisory at the time the author was removed as a collaborator. Only populated at removal time."
    end
  end

  def self.down
    change_table :repository_advisories, bulk: true do |t|
      t.remove :frozen_description
      t.remove :frozen_title
    end
  end
end
