# typed: true
class AddStarredRelationshipsFilter < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :for_you_feed_filter_settings, :starred_relationships_enabled, :boolean, default: true, null: false
  end
end
