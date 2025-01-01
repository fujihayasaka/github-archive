# typed: true

class ImmutableActionsOptOuts < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def change
    create_table :immutable_actions_opt_outs, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :workflow_repo_owner_id, null: false, unsigned: true
      t.timestamps

      t.index :workflow_repo_owner_id, unique: true
    end
  end
end
