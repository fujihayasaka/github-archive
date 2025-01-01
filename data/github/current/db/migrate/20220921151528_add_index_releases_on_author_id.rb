# typed: true
class AddIndexReleasesOnAuthorId < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :releases, bulk: true do |t|
      t.index [:author_id]
    end
  end
end
