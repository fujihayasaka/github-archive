# typed: true

class UsePushesIdSeq < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def change
    add_auto_increment(:pushes, :id, :pushes_id_seq)
  end
end
