# typed: true
class CreateCopilotEngagedOssRepository < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_engaged_oss_repositories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint   :repository_id, unsigned: true, null: false, index: { unique: true }, comment: "The repository"
      t.bigint   :language_name_id, unsigned: true, null: false, comment: "The language the repository qualifies for engaged oss"
      t.bigint   :license_id, unsigned: true, null: false, comment: "The license the repository uses"
      t.bigint   :rank, unsigned: true, null: false, default: 0, comment: "The rank of the repository for the language"
      t.bigint   :stargazer_count, unsigned: true, null: false, default: 0, comment: "The number of stargazers the repository has when updated"
      t.bigint   :fork_count, unsigned: true, null: false, default: 0, comment: "The number of forks the repository has when updated"
      t.datetime :last_pushed_at, precision: 6, null: true, comment: "The last time the repository was pushed to when updated"
      t.timestamps
    end
  end
end
