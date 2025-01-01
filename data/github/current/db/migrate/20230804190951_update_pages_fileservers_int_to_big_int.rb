class UpdatePagesFileserversIntToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)
  def change
    change_table :pages_fileservers, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
    end
  end
end
