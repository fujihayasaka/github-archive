# typed: true
# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys

class AddVerifiedCommitsTable < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Commits)

  def change
    create_table :verified_commits, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :oid, "binary(20)", null: false, primary_key: true
    end
  end
end
