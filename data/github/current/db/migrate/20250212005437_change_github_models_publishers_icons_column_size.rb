# typed: true

class ChangeGitHubModelsPublishersIconsColumnSize < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::GitHubModels)

  def up
    change_table :models_publishers, bulk: true do |t|
      t.change :dark_mode_icon, :mediumblob
      t.change :light_mode_icon, :mediumblob
    end
  end

  def down
    change_table :models_publishers, bulk: true do |t|
      t.change :dark_mode_icon, :blob
      t.change :light_mode_icon, :blob
    end
  end
end
