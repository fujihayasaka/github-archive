# typed: true
class AddStaleAtToFlipperFeatures < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Features)
  def change
    add_column :flipper_features, :stale_at, :datetime, precision: 6
  end
end
