class DropRenderBlobs < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Assets)
  def change
    drop_table :render_blobs, if_exists: true
  end
end
