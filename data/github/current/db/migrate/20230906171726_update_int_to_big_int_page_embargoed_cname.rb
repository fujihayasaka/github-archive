class UpdateIntToBigIntPageEmbargoedCname < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesBallast)
  def change
    change_table :pages_embargoed_cnames, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :previous_owner_id, :bigint, unsigned: true, null: false
      t.change :previous_repository_id, :bigint, unsigned: true, null: false
    end
  end
end
