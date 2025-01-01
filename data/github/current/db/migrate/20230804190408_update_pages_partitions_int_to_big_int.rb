class UpdatePagesPartitionsIntToBigInt < ActiveRecord::Migration[7.1]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Repositories)
  def change
    change_table :pages_partitions, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
    end
  end
end
