# typed: true
class CreateRepositoryRulesetHistory < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :repository_ruleset_histories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|

      t.bigint :repository_ruleset_id, unsigned: true, null: false
      t.json :state, null: false
      t.bigint :updated_by_id, unsigned: true, null: false

      t.timestamps

      t.index [:repository_ruleset_id, :created_at], name: "index_ruleset_history_on_ruleset_id_and_created_at"
    end
  end
end
