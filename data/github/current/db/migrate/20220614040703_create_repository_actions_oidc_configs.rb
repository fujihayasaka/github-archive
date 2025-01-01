# typed: true
class CreateRepositoryActionsOIDCConfigs < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Oidc)

  def up
    create_table :repository_actions_oidc_configs, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, null: false, unsigned: true
      t.json :configuration, null: true
      t.timestamps
      t.index [:repository_id], unique: true
    end
  end

  def down
    drop_table :repository_actions_oidc_configs
  end

end
