# typed: true

class CreateRefPushesInPushesCluster < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def change
    return unless (Rails.env.test? || Rails.env.development?) && !GitHub.enterprise? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    create_table :ref_pushes, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :repository_id, :bigint, unsigned: true, null: false
      t.column :pusher_id, :bigint, unsigned: true, null: false
      t.column :ref, "varbinary(1024)", null: false
      t.column :after, "varchar(40)", null: false
      t.column :pushed_at, "datetime(6)", null: false

      t.index [:repository_id, :pusher_id, :ref], unique: true, name: "index_ref_pushes_on_repository_id_and_pusher_id_and_ref"
      t.index [:repository_id, :ref, :pusher_id], unique: true, name: "index_ref_pushes_on_repository_id_and_ref_and_pusher_id"
    end

    add_vindex :ref_pushes, :hash, :repository_id
    add_auto_increment :ref_pushes, :id, :ref_pushes_id_seq
  end
end
