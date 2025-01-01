# typed: true

# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
# rubocop:disable GitHub/ConnectionClassPresentInMigration

class AddVerifiedCommitsTable < ActiveRecord::Migration[7.2]
  def change
    if GitHub.enterprise?
      create_table :verified_commits, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
        t.column :oid, "binary(20)", null: false, primary_key: true
      end
    end
  end
end
