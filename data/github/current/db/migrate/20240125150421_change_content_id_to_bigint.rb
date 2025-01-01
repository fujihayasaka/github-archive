class ChangeContentIdToBigint < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesBallast)
  def change
    change_table :content_references, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :user_id, :bigint, unsigned: true
      t.change :content_id, :bigint, unsigned: true
    end
  end
end
