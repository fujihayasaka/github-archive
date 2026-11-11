# typed: true

class AddRepositoryActivityToFeedFilterSettings < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :for_you_feed_filter_settings, :repository_activity_enabled, :boolean, default: true, null: false
  end
end
